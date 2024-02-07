// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "./interfaces/ITNGBLV3Oracle.sol";

/**
 * @title TNGBLV3Oracle
 * @author Veljko Mihailovic
 */
contract TNGBLV3Oracle is ITNGBLV3Oracle {
    address public constant uniV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    uint24 public constant poolFeeDefault = 3000;

    function consult(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint24 secondsAgo
    ) external view override returns (uint256 amountOut) {
        address _pool = _fetchPool(tokenIn, tokenOut, poolFeeDefault);
        require(_pool != address(0), "pool doesn't exist");
        amountOut = _estimateAmountOut(tokenIn, tokenOut, _pool, amountIn, secondsAgo);
    }

    function consultWithFee(
        address tokenIn,
        uint128 amountIn,
        address tokenOut,
        uint32 secondsAgo,
        uint24 fee
    ) external view override returns (uint256 amountOut) {
        address _pool = _fetchPool(tokenIn, tokenOut, fee);
        require(_pool != address(0), "pool doesn't exist");

        amountOut = _estimateAmountOut(tokenIn, tokenOut, _pool, amountIn, secondsAgo);
    }

    function _fetchPool(
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) internal view returns (address pool) {
        pool = IUniswapV3Factory(uniV3Factory).getPool(tokenIn, tokenOut, fee);
    }

    function _estimateAmountOut(
        address tokenIn,
        address tokenOut,
        address pool,
        uint128 amountIn,
        uint32 secondsAgo
    ) internal view returns (uint256 amountOut) {
        // Code copied from OracleLibrary.sol, consult()
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        // int56 since tick * time = int24 * uint32
        // 56 = 24 + 32
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(tickCumulativesDelta / secondsAgo);
        // Always round to negative infinity
        /*
        int doesn't round down when it is negative
        int56 a = -3
        -3 / 10 = -3.3333... so round down to -4
        but we get
        a / 10 = -3
        so if tickCumulativeDelta < 0 and division has remainder, then round
        down
        */
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % secondsAgo != 0)) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }
}
