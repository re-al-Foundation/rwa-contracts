// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./ITangibleNFT.sol";
import "./IPriceOracle.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ITangiblePriceManager interface gives prices for categories added in TangiblePriceManager.
interface ITangiblePriceManager {
    /// @dev The function returns contract oracle for category.
    function oracleForCategory(ITangibleNFT category) external view returns (IPriceOracle);

    /// @dev The function returns current price from oracle for provided category.
    function setOracleForCategory(ITangibleNFT category, IPriceOracle oracle) external;
}
