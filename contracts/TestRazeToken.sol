// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/presets/ERC20PresetMinterPauser.sol";
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/presets/ERC20PresetMinterPauser.sol

contract TestRazeToken is ERC20PresetMinterPauser {

    constructor() ERC20PresetMinterPauser("TestRazeToken", "Raze") public {
    }

}
