// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface IExchange {
    function quoteOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256);

    /// @dev Performs an exchange of two Erc20 tokens and returns an amount of `tokenOut`.
    function exchange(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256);
}
