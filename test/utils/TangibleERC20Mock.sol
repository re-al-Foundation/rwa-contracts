// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TangibleERC20Mock is ERC20, AccessControl {
    bytes32 public constant BURNER_ROLE = keccak256("BURNER");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    uint256 public constant MAX_SUPPLY = 33333333e18;

    constructor() ERC20("Tangible", "TNGBL") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function burnFrom(address who, uint256 amount) public onlyRole(BURNER_ROLE) {
        uint256 currentAllowance = allowance(who, msg.sender);
        require(currentAllowance >= amount, "burn amount exceeds allowance");
        unchecked {
            _approve(who, msg.sender, currentAllowance - amount);
        }
        _burn(who, amount);
    }

    function mint(uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(msg.sender, amount);
    } 

    function mintFor(address who, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(who, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        require(totalSupply() <= MAX_SUPPLY, "max. supply exceeded");
    }
}
