// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./RazeBase.sol";

contract RazeETH is RazeBase {

    constructor(address _transfer, address _redeem, uint256 _unit) RedeemBase(_transfer, _redeem, _unit) public {
    }

    function mint(Utils.G1Point memory y, uint256 unitAmount, bytes memory encGuess) public payable {
        uint256 mUnitAmount = toUnitAmount(msg.value);
        require(unitAmount == mUnitAmount, "[Raze mint] Specified mint amount is differnet from the paid amount.");

        mintBase(y, unitAmount, encGuess);
    }

    function redeem(Utils.G1Point memory y, uint256 unitAmount, Utils.G1Point memory u, bytes memory proof, bytes memory encGuess) public {
        uint256 nativeAmount = toNativeAmount(unitAmount);
        uint256 fee = nativeAmount * redeem_fee_numerator / redeem_fee_denominator; 

        redeemBase(y, unitAmount, u, proof, encGuess);

        if (fee > 0) {
            raze_agency.transfer(fee);
            redeem_fee_log = redeem_fee_log + fee;
        }
        msg.sender.transfer(nativeAmount-fee);
    }
}


