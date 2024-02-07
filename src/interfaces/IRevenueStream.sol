// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Interface for RevenueStream contract.
interface IRevenueStream {

    function revenueToken() external view returns (IERC20);

    function claimable(address account) external view returns (uint256 amount);

    function claim(address account) external returns (uint256 amount);

    function deposit(uint256 amount) external;

    function getCyclesArray() external view returns (uint256[] memory);

    function currentCycle() external view returns (uint256 cycle);
}