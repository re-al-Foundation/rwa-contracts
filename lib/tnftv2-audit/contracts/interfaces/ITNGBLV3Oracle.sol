// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.0 <=0.8.21;

interface ITNGBLV3Oracle {
    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - [windowSize, windowSize - periodSize * 2], now]
    // update must have been called for the bucket corresponding to timestamp `now - windowSize`
    function consult(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint24 secondsAgo
    ) external view returns (uint256);

    function consultWithFee(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint32 secondsAgo,
        uint24 fee
    ) external view returns (uint256);
}
