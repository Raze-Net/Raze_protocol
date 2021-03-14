// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./RazeTransfer.sol";
import "./RazeRedeem.sol";

contract RazeBase {

    using Utils for uint256;
    using Utils for Utils.G1Point;

    /*
       Max units that can be handled by raze.
    */
    uint256 public constant MAX = 2**32-1;

    /* 
       The # of tokens that constitute one unit.
       Balances, mints, redeems, and transfers are all interpreted in terms of unit, rather than token. 
    */
    uint256 public unit; 

    uint256 public round_len = 24; 
    uint256 public round_base = 0; // 0 for block, 1 for second (usually just for test)


    address payable public raze_agency; 

    /* redeem fee: 1/100 of redeem amount */
    uint256 public redeem_fee_numerator = 1;
    uint256 public redeem_fee_denominator = 100;
    /* transfer fee: 1/5 of gas */
    uint256 public transfer_fee_numerator = 1;
    uint256 public transfer_fee_denominator = 5;

    RazeTransfer raze_transfer;
    RazeRedeem raze_redeem;

    uint256 public balance_log = 0;
    uint256 public users_log = 0;
    uint256 public redeem_fee_log = 0;
    uint256 public transfer_fee_log = 0;
    uint256 public deposits_log = 0;
    uint256 public mint_count_log = 0;
    

    mapping(bytes32 => Utils.G1Point[2]) acc; // main account mapping
    mapping(bytes32 => Utils.G1Point[2]) pending; // storage for pending transfers
    mapping(bytes32 => uint256) public last_roll_over;
    bytes32[] nonce_set; // would be more natural to use a mapping, but they can't be deleted / reset!
    uint256 public last_global_update = 0; // will be also used as a proxy for "current round", seeing as rollovers will be anticipated
    //// not implementing account locking for now...revisit

    mapping(bytes32 => bytes) guess;

    event TransferOccurred(Utils.G1Point[] parties); // all parties will be notified, client can determine whether it was real or not.
    //// arg is still necessary for transfers---not even so much to know when you received a transfer, as to know when you got rolled over.
    event LogUint256(string label, uint256 indexed value);

    constructor(address _transfer, address _redeem, uint256 _unit) public {
        raze_agency = msg.sender;
        raze_transfer = RazeTransfer(_transfer);
        raze_redeem = RazeRedeem(_redeem);
        unit = _unit;
    }

    function toUnitAmount(uint256 nativeAmount) internal view returns (uint256) {
        require(nativeAmount % unit == 0, "Native amount must be multiple of a unit.");
        uint256 amount = nativeAmount / unit;
        require(0 <= amount && amount <= MAX, "Amount out of range."); 
        return amount;
    }

    function toNativeAmount(uint256 unitAmount) internal view returns (uint256) {
        require(0 <= unitAmount && unitAmount <= MAX, "Amount out of range");
        return unitAmount * unit;
    }

    function setRedeemFeeStrategy(uint256 numerator, uint256 denominator) public {
        require(msg.sender == raze_agency, "Permission denied: Only admin can change redeem fee strategy.");
        redeem_fee_numerator = numerator;
        redeem_fee_denominator = denominator;
    }

    function setTransferFeeStrategy(uint256 numerator, uint256 denominator) public {
        require(msg.sender == raze_agency, "Permission denied: Only admin can change transfer fee strategy.");
        transfer_fee_numerator = numerator;
        transfer_fee_denominator = denominator;
    }

    function setRoundBase (uint256 _round_base) public {
        require(msg.sender == raze_agency, "Permission denied: Only admin can change round base.");
        round_base = _round_base;
    }

    function setRoundLen (uint256 _round_len) public {
        require(msg.sender == raze_agency, "Permission denied: Only admin can change round length.");
        round_len = _round_len;
    }

    function setUnit (uint256 _unit) public {
        require(msg.sender == raze_agency, "Permission denied: Only admin can change unit.");
        unit = _unit;
    }

    function setRazeAgency (address payable _raze_agency) public {
        require(msg.sender == raze_agency, "Permission denied: Only admin can change agency.");
        raze_agency = _raze_agency;
    }

    function register(Utils.G1Point memory y, uint256 c, uint256 s) public {
        // allows y to participate. c, s should be a Schnorr signature on "this"
        Utils.G1Point memory K = Utils.g().pMul(s).pAdd(y.pMul(c.gNeg()));
        uint256 challenge = uint256(keccak256(abi.encode(address(this), y, K))).gMod();
        require(challenge == c, "Invalid registration signature!");
        bytes32 yHash = keccak256(abi.encode(y));
        require(!registered(yHash), "Account already registered!");
        // pending[yHash] = [y, Utils.g()]; // "not supported" yet, have to do the below

        /*
            The following initial value of pending[yHash] is equivalent to an ElGamal encryption of m = 0, with nonce r = 1:
            (mG + ry, rG) --> (y, G)
            If we don't set pending in this way, then we can't differentiate two cases:
            1. The account is not registered (both acc and pending are 0, because `mapping` has initial value for all keys)
            2. The account has a total balance of 0 (both acc and pending are 0)

            With such a setting, we can guarantee that, once an account is registered, its `acc` and `pending` can never (crytographically negligible) BOTH equal to Point zero.
            NOTE: `pending` can be reset to Point zero after a roll over.
        */
        pending[yHash][0] = y;
        pending[yHash][1] = Utils.g();

        users_log = users_log + 1;
    }

    function registered(bytes32 yHash) public view returns (bool) {
        Utils.G1Point memory zero = Utils.G1Point(0, 0);
        Utils.G1Point[2][2] memory scratch = [acc[yHash], pending[yHash]];
        return !(scratch[0][0].pEqual(zero) && scratch[0][1].pEqual(zero) && scratch[1][0].pEqual(zero) && scratch[1][1].pEqual(zero));
    }

    /**
      Get the current balances of accounts. If the given `round` is larger than the last roll over round, the returned balances
      will include pending transfers. 
    */
    function getBalance(Utils.G1Point[] memory y, uint256 round) view public returns (Utils.G1Point[2][] memory accounts) {
        // in this function and others, i have to use public + memory (and hence, a superfluous copy from calldata)
        // only because calldata structs aren't yet supported by solidity. revisit this in the future.
        uint256 size = y.length;
        accounts = new Utils.G1Point[2][](size);
        for (uint256 i = 0; i < size; i++) {
            bytes32 yHash = keccak256(abi.encode(y[i]));
            accounts[i] = acc[yHash];
            if (last_roll_over[yHash] < round) {
                Utils.G1Point[2] memory scratch = pending[yHash];
                accounts[i][0] = accounts[i][0].pAdd(scratch[0]);
                accounts[i][1] = accounts[i][1].pAdd(scratch[1]);
            }
        }
    }

    function getAccountState (Utils.G1Point memory y) public view returns (Utils.G1Point[2] memory y_available, Utils.G1Point[2] memory y_pending) {
        bytes32 yHash = keccak256(abi.encode(y));
        y_available = acc[yHash];
        y_pending = pending[yHash];
        return (y_available, y_pending);
    }

    function getGuess (Utils.G1Point memory y) public view returns (bytes memory y_guess) {
        bytes32 yHash = keccak256(abi.encode(y));
        y_guess = guess[yHash];
        return y_guess;
    }

    function rollOver(bytes32 yHash) internal {
        uint256 e = 0;
        if (round_base == 0)
            e = block.number / round_len;
        else if (round_base == 1)
            e = block.timestamp / round_len;
        else
            revert("Invalid round base.");

        if (last_roll_over[yHash] < e) {
            Utils.G1Point[2][2] memory scratch = [acc[yHash], pending[yHash]];
            acc[yHash][0] = scratch[0][0].pAdd(scratch[1][0]);
            acc[yHash][1] = scratch[0][1].pAdd(scratch[1][1]);
            // acc[yHash] = scratch[0]; // can't do this---have to do the above instead (and spend 2 sloads / stores)---because "not supported". revisit
            delete pending[yHash]; // pending[yHash] = [Utils.G1Point(0, 0), Utils.G1Point(0, 0)];
            last_roll_over[yHash] = e;
        }
        if (last_global_update < e) {
            last_global_update = e;
            delete nonce_set;
        }
    }

    function mintBase(Utils.G1Point memory y, uint256 amount, bytes memory encGuess) internal {

        require(amount <= MAX && balance_log + amount <= MAX, "[Raze mint] Mint pushes contract past maximum value.");
        balance_log += amount;
        deposits_log += amount;
        mint_count_log += 1;

        bytes32 yHash = keccak256(abi.encode(y));
        require(registered(yHash), "[Raze mint] Account not yet registered.");
        rollOver(yHash);

        Utils.G1Point memory scratch = pending[yHash][0];
        scratch = scratch.pAdd(Utils.g().pMul(amount));
        pending[yHash][0] = scratch;

        guess[yHash] = encGuess;
    }

    function redeemBase(Utils.G1Point memory y, uint256 amount, Utils.G1Point memory u, bytes memory proof, bytes memory encGuess) internal {

        require(balance_log >= amount, "[Raze redeem] Failed: Invalid redeem amount.");
        balance_log -= amount;
        

        bytes32 yHash = keccak256(abi.encode(y));
        require(registered(yHash), "[Raze redeem] Account not yet registered.");
        rollOver(yHash);

        Utils.G1Point[2] memory scratch = pending[yHash];
        pending[yHash][0] = scratch[0].pAdd(Utils.g().pMul(amount.gNeg()));

        scratch = acc[yHash]; // simulate debit of acc---just for use in verification, won't be applied
        scratch[0] = scratch[0].pAdd(Utils.g().pMul(amount.gNeg()));
        bytes32 uHash = keccak256(abi.encode(u));
        for (uint256 i = 0; i < nonce_set.length; i++) {
            require(nonce_set[i] != uHash, "[Raze redeem] Nonce already seen!");
        }
        nonce_set.push(uHash);

        guess[yHash] = encGuess;

        RazeRedeem.Statment memory raze_stm = raze_redeem.wrapStatement(scratch[0], scratch[1], y, last_global_update, u, msg.sender);
        RazeRedeem.Proof memory raze_proof = raze_redeem.unserialize(proof);

        require(raze_redeem.verify(raze_stm, raze_proof), "[Raze redeem] Failed: verification!");
    }

    function transfer(Utils.G1Point[] memory C, Utils.G1Point memory D, 
                      Utils.G1Point[] memory y, Utils.G1Point memory u, 
                      bytes memory proof) public payable {

        uint256 startGas = gasleft();

        // TODO: check that sender and receiver should NOT be equal.
        uint256 size = y.length;
        Utils.G1Point[] memory CLn = new Utils.G1Point[](size);
        Utils.G1Point[] memory CRn = new Utils.G1Point[](size);
        require(C.length == size, "[Raze transfer] Input array length mismatch!");


        for (uint256 i = 0; i < size; i++) {
            bytes32 yHash = keccak256(abi.encode(y[i]));
            require(registered(yHash), "[Raze transfer] Account not yet registered.");
            rollOver(yHash);
            Utils.G1Point[2] memory scratch = pending[yHash];
            pending[yHash][0] = scratch[0].pAdd(C[i]);
            pending[yHash][1] = scratch[1].pAdd(D);
            // pending[yHash] = scratch; // can't do this, so have to use 2 sstores _anyway_ (as in above)

            scratch = acc[yHash];
            CLn[i] = scratch[0].pAdd(C[i]);
            CRn[i] = scratch[1].pAdd(D);
        }

        bytes32 uHash = keccak256(abi.encode(u));
        for (uint256 i = 0; i < nonce_set.length; i++) {
            require(nonce_set[i] != uHash, "[Raze transfer] Nonce already seen!");
        }
        nonce_set.push(uHash);

        RazeTransfer.Statement memory raze_stm = raze_transfer.wrapStatement(CLn, CRn, C, D, y, last_global_update, u);
        RazeTransfer.Proof memory raze_proof = raze_transfer.unserialize(proof);

        require(raze_transfer.verify(raze_stm, raze_proof), "[Raze transfer] Failed: verification");

        uint256 usedGas = startGas - gasleft();
        
        uint256 fee = (usedGas * transfer_fee_numerator / transfer_fee_denominator) * tx.gasprice;
        if (fee > 0) {
            require(msg.value >= fee, "[Raze transfer] Not enough fee sent with the transfer transaction.");
            raze_agency.transfer(fee);
            transfer_fee_log = transfer_fee_log + fee;
        }
        msg.sender.transfer(msg.value - fee);

        emit TransferOccurred(y);
    }


}


