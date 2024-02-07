// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IRouter {
    struct Route {
        address from;
        address to;
        bool stable;
    }

    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amount, bool stable);

    function getAmountsOut(
        uint256 amountIn,
        Route[] calldata routes
    ) external view returns (uint256[] memory amounts);

    function swapExactTokensForTokensSimple(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
