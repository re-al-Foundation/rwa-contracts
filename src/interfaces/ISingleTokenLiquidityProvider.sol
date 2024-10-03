// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPair.sol";

interface ISingleTokenLiquidityProvider {
    /// @notice Adds liquidity for a given pair using a given token.
    /// @param _pair Pair to provide liquidity for.
    /// @param _token Token address to provide liquidity with.
    /// @param _amount Amount of token to provide.
    /// @param _swapAmount The amount of tokens to swap for the other pair token.
    /// @param _minLiquidity Minimum liquidity to provide.
    /// @return _liquidity The amount of liquidity added.
    function addLiquidity(
        IPair _pair,
        address _token,
        uint256 _amount,
        uint256 _swapAmount,
        uint256 _minLiquidity
    ) external returns (uint256 _liquidity);
}
