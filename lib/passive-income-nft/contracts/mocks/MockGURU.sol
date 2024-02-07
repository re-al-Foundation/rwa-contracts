// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockGURU is ERC20, ERC20Burnable {
    constructor() ERC20("Guru", "GURU") {
        _mint(msg.sender, 1e13);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }
}
