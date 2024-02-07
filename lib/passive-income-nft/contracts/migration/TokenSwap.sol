// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ERC20Burnable.sol";
import "../interfaces/ERC20Mintable.sol";

contract TangibleTokenSwap is AccessControl {
    bytes32 public constant SWAPPER_ROLE = keccak256("SWAPPER");

    address public immutable GURU;
    address public immutable TNGBL;

    uint256 private immutable _multiplier;

    constructor(address nidhiToken, address tangibleToken) {
        GURU = nidhiToken;
        TNGBL = tangibleToken;
        _multiplier =
            10 **
                (IERC20Metadata(tangibleToken).decimals() -
                    IERC20Metadata(nidhiToken).decimals());
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function initialize() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ERC20 guru = ERC20(GURU);
        ERC20 tngbl = ERC20(TNGBL);
        uint256 balance = tngbl.balanceOf(address(this));
        uint256 totalSupply = guru.totalSupply() * _multiplier;
        if (totalSupply > balance) {
            ERC20Mintable(TNGBL).mint(totalSupply - balance);
        } else if (totalSupply < balance) {
            ERC20Burnable(TNGBL).burn(balance - totalSupply);
        }
    }

    function swap(uint256 amount)
        external
        onlyRole(SWAPPER_ROLE)
        returns (uint256 amountOut)
    {
        amountOut = amount * _multiplier;
        require(
            amountOut <= ERC20(TNGBL).balanceOf(address(this)),
            "swap contract out of funds"
        );
        ERC20Burnable(GURU).burnFrom(msg.sender, amount);
        SafeERC20.safeTransfer(IERC20(TNGBL), msg.sender, amountOut);
    }
}
