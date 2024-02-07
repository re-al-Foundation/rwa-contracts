// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

/// @dev Interface for RevenueStream contract.
interface IRevenueStreamETH {
    
    function claimable(address account) external view returns (uint256 amount);

    function claimETH(address account) external returns (uint256 amount);

    function depositETH() payable external;

    function getCyclesArray() external view returns (uint256[] memory);

    function currentCycle() external view returns (uint256 cycle);
}