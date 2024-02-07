// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ITangibleRevenueShare {
    function revenueToken() external view returns (address);

    function claimForToken(address tnft, uint256 tokenId) external;
}

contract MockTngblRent is ITangibleRevenueShare {
    using SafeERC20 for IERC20;
    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    function revenueToken() external view override returns (address) {
        return usdc;
    }

    function claimForToken(address tnft, uint256 tokenId) external override {
        require(msg.sender == 0x7eEf3770027a5Ccc6788c2456b7AD37BE0cc5ea4, "not treasury");
        IERC20(usdc).safeTransfer(msg.sender, IERC20(usdc).balanceOf(address(this)));
    }
}
