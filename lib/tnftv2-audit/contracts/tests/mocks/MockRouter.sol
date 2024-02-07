// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ERC20Mintable {
    function mint(address _to, uint256 _amount) external;

    function burn(uint256 _amount) external;
}

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

contract MockRouter is IRouter {
    function toDecimals(
        uint256 amount,
        uint8 fromDecimal,
        uint8 toDecimal
    ) internal pure returns (uint256) {
        require(toDecimal >= uint8(0) && toDecimal <= uint8(18), "Invalid _decimals");
        if (fromDecimal > toDecimal) {
            amount = amount / (10 ** (fromDecimal - toDecimal));
        } else if (fromDecimal < toDecimal) {
            amount = amount * (10 ** (toDecimal - fromDecimal));
        }
        return amount;
    }

    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view override returns (uint256 amount, bool stable) {
        // Mock implementation, return amountIn in tokenOut decimals
        uint8 tokenOutDecimals = IERC20Metadata(tokenOut).decimals();
        uint8 tokenInDecimals = IERC20Metadata(tokenIn).decimals();
        return (toDecimals(amountIn, tokenInDecimals, tokenOutDecimals), true);
    }

    function getAmountsOut(
        uint256 amountIn,
        Route[] calldata routes
    ) external view override returns (uint256[] memory amounts) {
        // Mock implementation, return any values you need for testing
        uint256 length = routes.length;
        uint256[] memory result = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            result[i] = amountIn;
            unchecked {
                ++i;
            }
        }
        uint8 tokenOutDecimals = IERC20Metadata(routes[0].from).decimals();
        uint8 tokenInDecimals = IERC20Metadata(routes[length - 1].to).decimals();
        result[length - 1] = toDecimals(amountIn, tokenInDecimals, tokenOutDecimals);
        return result;
    }

    function swapExactTokensForTokensSimple(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        require(deadline <= block.timestamp, "expired");
        // Mock implementation, mint tokenOut and transfer it to 'to' address
        uint8 tokenInDecimals = IERC20Metadata(tokenFrom).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(tokenTo).decimals();
        uint256 amountOut = toDecimals(amountIn, tokenInDecimals, tokenOutDecimals);

        IERC20(tokenFrom).transferFrom(msg.sender, address(this), amountIn);
        ERC20Mintable(tokenFrom).burn(amountIn);
        ERC20Mintable(tokenTo).mint(to, amountOut);

        uint256[] memory result = new uint256[](2);
        result[0] = amountIn;
        result[1] = amountOut;
        require(amountOut == amountOutMin, "min not satisfied");
        return result;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        // Mock implementation, mint tokenOut and transfer it to 'to' address
        require(deadline <= block.timestamp, "expired");
        uint256 length = routes.length;
        uint8 tokenInDecimals = IERC20Metadata(routes[0].from).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(routes[length - 1].to).decimals();
        uint256 amountOut = toDecimals(amountIn, tokenInDecimals, tokenOutDecimals);
        IERC20(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        ERC20Mintable(routes[0].from).burn(amountIn);
        ERC20Mintable(routes[length - 1].to).mint(to, amountOut);

        uint256[] memory result = new uint256[](routes.length);
        for (uint256 i = 0; i < routes.length; i++) {
            result[i] = amountIn;
        }
        require(amountOut == amountOutMin, "min not satisfied");
        result[length - 1] = amountOut;
        return result;
    }
}
