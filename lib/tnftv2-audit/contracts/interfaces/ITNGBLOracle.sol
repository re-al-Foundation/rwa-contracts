// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.6;

interface ITNGBLOracle {
    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint256 timestamp) external view returns (uint8 index);

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update(address tokenA, address tokenB) external;

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - [windowSize, windowSize - periodSize * 2], now]
    // update must have been called for the bucket corresponding to timestamp `now - windowSize`
    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOut);
}
