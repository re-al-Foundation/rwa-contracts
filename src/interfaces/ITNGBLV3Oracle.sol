// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ITNGBLV3Oracle {
    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - [windowSize, windowSize - periodSize * 2], now]
    // update must have been called for the bucket corresponding to timestamp `now - windowSize`
    function consult001(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint32 secondsAgo
    ) external view returns (uint256);

    function consult03(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint32 secondsAgo
    ) external view returns (uint256);

    function consult005(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint32 secondsAgo
    ) external view returns (uint256);

    function consult1(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint32 secondsAgo
    ) external view returns (uint256);

    function consultWithFee(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint32 secondsAgo,
        uint24 fee
    ) external view returns (uint256);

    function POOL_FEE_001() external view returns (uint24);

    function POOL_FEE_00001() external view returns (uint24);

    function POOL_FEE_005() external view returns (uint24);

    function POOL_FEE_03() external view returns (uint24);

    function POOL_FEE_1() external view returns (uint24);

    function POOL_FEE_100() external view returns (uint24);

    function POOL_FEE_01() external view returns (uint24);
}