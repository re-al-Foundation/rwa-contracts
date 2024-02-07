// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ISellFeeDistributor interface defines the interface of the SellFeeDistributor which manages fee distribution.
interface ISellFeeDistributor {
    /// @dev This function distributes fees.
    function distributeFee(IERC20 paymentToken, uint256 feeAmount) external;
}
