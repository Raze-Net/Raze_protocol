// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./RazeIP.sol";

contract RazeRedeem {
    using Utils for uint256;
    using Utils for Utils.G1Point;

    RazeIP ip;

    struct Statement {
        Utils.G1Point ct_l;
        Utils.G1Point ct_r;
        Utils.G1Point pk;
        uint256 epoch; 
        Utils.G1Point u;
        address sender;
    }

    struct Proof {
        Utils.G1Point BA;
        Utils.G1Point BS;

        Utils.G1Point[2] tCommits;
        uint256 tHat;
        uint256 mu;

        uint256 c;
        uint256 s_sk;
        uint256 s_b;
        uint256 s_tau;

        RazeIP.Proof ip_proof;
    }

    constructor(address _ip) public {
        ip = RazeIP(_ip);
    }

    struct RedeemInfo {
        uint256 y;
        uint256[32] ys;
        uint256 z;
        uint256 z2; 
        uint256 z3;
        uint256[32] twoTimesZSquared;
        uint256 x;
        uint256 t;
        uint256 k;
        Utils.G1Point tEval;
    }

    struct SigmaInfo {
        uint256 c;
        Utils.G1Point A_y;
        Utils.G1Point A_b;
        Utils.G1Point A_t;
        Utils.G1Point gEpoch;
        Utils.G1Point A_u;
    }

    struct IPInfo {
        Utils.G1Point P;
        Utils.G1Point u_x;
        Utils.G1Point[] hPrimes;
        Utils.G1Point hPrimeSum;
        uint256 o;
    }

    function gSum() internal pure returns (Utils.G1Point memory) {
        return Utils.G1Point(0x2257118d30fe5064dda298b2fac15cf96fd51f0e7e3df342d0aed40b8d7bb151, 0x0d4250e7509c99370e6b15ebfe4f1aa5e65a691133357901aa4b0641f96c80a8);
    }

    function verify(Statement memory statement, Proof memory proof) internal view returns (bool) {
        uint256 statementHash = uint256(keccak256(abi.encode(statement.ct_l, statement.ct_r, statement.pk, statement.epoch, statement.sender))).gMod();

        RedeemInfo memory redeem_info;
        redeem_info.y = uint256(keccak256(abi.encode(statementHash, proof.BA, proof.BS))).gMod();
        redeem_info.ys[0] = 1;
        redeem_info.k = 1;
        for (uint256 i = 1; i < 32; i++) {
            redeem_info.ys[i] = redeem_info.ys[i - 1].gMul(redeem_info.y);
            redeem_info.k = redeem_info.k.gAdd(redeem_info.ys[i]);
        }
        redeem_info.z = uint256(keccak256(abi.encode(redeem_info.y))).gMod();
        redeem_info.z2 = redeem_info.z.gExp(2);
        redeem_info.z3 = redeem_info.z2.gMul(redeem_info.z); 
        redeem_info.k = redeem_info.k.gMul(redeem_info.z.gSub(redeem_info.z2)).gSub(redeem_info.z3.gMul(2 ** 32).gSub(redeem_info.z3));
        redeem_info.t = proof.tHat.gSub(redeem_info.k);
        for (uint256 i = 0; i < 32; i++) {
            redeem_info.twoTimesZSquared[i] = redeem_info.z2.gMul(2 ** i);
        }

        redeem_info.x = uint256(keccak256(abi.encode(redeem_info.z, proof.tCommits))).gMod();
        redeem_info.tEval = proof.tCommits[0].pMul(redeem_info.x).pAdd(proof.tCommits[1].pMul(redeem_info.x.gMul(redeem_info.x))); 
        SigmaInfo memory sigma_info;
        sigma_info.A_y = Utils.g().pMul(proof.s_sk).pAdd(statement.pk.pMul(proof.c.gNeg()));
        sigma_info.A_b = Utils.g().pMul(proof.s_b).pAdd(statement.ct_r.pMul(proof.s_sk).pAdd(statement.ct_l.pMul(proof.c.gNeg())).pMul(redeem_info.z2));
        sigma_info.A_t = Utils.g().pMul(redeem_info.t).pAdd(redeem_info.tEval.pNeg()).pMul(proof.c).pAdd(Utils.h().pMul(proof.s_tau)).pAdd(Utils.g().pMul(proof.s_b.gNeg()));
        sigma_info.gEpoch = Utils.mapInto("Raze", statement.epoch);
        sigma_info.A_u = sigma_info.gEpoch.pMul(proof.s_sk).pAdd(statement.u.pMul(proof.c.gNeg()));

        sigma_info.c = uint256(keccak256(abi.encode(redeem_info.x, sigma_info.A_y, sigma_info.A_b, sigma_info.A_t, sigma_info.A_u))).gMod();
        require(sigma_info.c == proof.c, string(abi.encodePacked("[Raze redeem] Sigma challenge failed: ", Utils.uint2str(statement.epoch))));

        IPInfo memory ip_info;
        ip_info.o = uint256(keccak256(abi.encode(sigma_info.c))).gMod();
        ip_info.u_x = Utils.g().pMul(ip_info.o);
        ip_info.hPrimes = new Utils.G1Point[](32);
        for (uint256 i = 0; i < 32; i++) {
            ip_info.hPrimes[i] = ip.hs(i).pMul(redeem_info.ys[i].gInv());
            ip_info.hPrimeSum = ip_info.hPrimeSum.pAdd(ip_info.hPrimes[i].pMul(redeem_info.ys[i].gMul(redeem_info.z).gAdd(redeem_info.twoTimesZSquared[i])));
        }
        ip_info.P = proof.BA.pAdd(proof.BS.pMul(redeem_info.x)).pAdd(gSum().pMul(redeem_info.z.gNeg())).pAdd(ip_info.hPrimeSum);
        ip_info.P = ip_info.P.pAdd(Utils.h().pMul(proof.mu.gNeg()));
        ip_info.P = ip_info.P.pAdd(ip_info.u_x.pMul(proof.tHat));
        require(ip.verifyInnerProduct(ip_info.hPrimes, ip_info.u_x, ip_info.P, proof.ip_proof, ip_info.o), "[Raze redeem] Inner product proof verification failed.");

        return true;
    }


    function wrapStatement (Utils.G1Point memory ct_l, Utils.G1Point memory ct_r, Utils.G1Point memory pk, uint256 epoch, Utils.G1Point memory u, address sender) public pure returns (Statement memory statement) {
        statement.ct_l = ct_l;
        statement.ct_r = ct_r;
        statement.pk = pk;
        statement.epoch = epoch;
        statement.u = u;
        statement.sender = sender;
        return statement;
    }


    function unserialize(bytes memory arr) internal pure returns (Proof memory proof) {
        proof.BA = Utils.G1Point(Utils.slice(arr, 0), Utils.slice(arr, 32));
        proof.BS = Utils.G1Point(Utils.slice(arr, 64), Utils.slice(arr, 96));

        proof.tCommits = [Utils.G1Point(Utils.slice(arr, 128), Utils.slice(arr, 160)), Utils.G1Point(Utils.slice(arr, 192), Utils.slice(arr, 224))];
        proof.tHat = uint256(Utils.slice(arr, 256));
        proof.mu = uint256(Utils.slice(arr, 288));

        proof.c = uint256(Utils.slice(arr, 320));
        proof.s_sk = uint256(Utils.slice(arr, 352));
        proof.s_b = uint256(Utils.slice(arr, 384));
        proof.s_tau = uint256(Utils.slice(arr, 416));

        RazeIP.Proof memory ip_proof;
        ip_proof.ls = new Utils.G1Point[](5);
        ip_proof.rs = new Utils.G1Point[](5);
        for (uint256 i = 0; i < 5; i++) { // 2^5 = 32.
            ip_proof.ls[i] = Utils.G1Point(Utils.slice(arr, 448 + i * 64), Utils.slice(arr, 480 + i * 64));
            ip_proof.rs[i] = Utils.G1Point(Utils.slice(arr, 448 + (5 + i) * 64), Utils.slice(arr, 480 + (5 + i) * 64));
        }
        ip_proof.a = uint256(Utils.slice(arr, 448 + 5 * 128));
        ip_proof.b = uint256(Utils.slice(arr, 480 + 5 * 128));
        proof.ip_proof = ip_proof;

        return proof;
    }
}
