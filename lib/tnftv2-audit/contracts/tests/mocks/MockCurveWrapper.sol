// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface USDMint {
    function mint(address to, uint256 amount) external;
}

interface DAIMint {
    function mint(uint256 amount) external;
}

contract MockCurveWrapper {
    using SafeERC20 for IERC20;

    IERC20 public immutable USDC = IERC20(0xA0fB0349526B7213b6be0F1D9A62f952A9179D96);
    IERC20 public immutable USDR = IERC20(0x41e6657D073c0e8E16d42Bf592BF5F6FA42D7fF3);
    IERC20 public immutable DAI = IERC20(0xEefB150e6986A70086D6761ec82023d2fd927169);

    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amountsIn) {
        require(path.length == 2, "invalid path length");
        uint256 amountInMax = convertToDecimal(
            IERC20Metadata(path[0]),
            amountOut,
            IERC20Metadata(path[1]).decimals()
        );
        amountsIn = new uint256[](2);
        amountsIn[0] = amountInMax;
        amountsIn[1] = amountOut;
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amountsOut) {
        require(path.length == 2, "invalid path length");
        uint256 amountOutMin = convertToDecimal(
            IERC20Metadata(path[1]),
            amountIn,
            IERC20Metadata(path[0]).decimals()
        );
        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        amountsOut[1] = amountOutMin;
    }

    function convertToDecimal(
        IERC20Metadata paymentToken,
        uint256 price,
        uint8 decimals
    ) internal view returns (uint256) {
        require(decimals > uint8(0) && decimals <= uint8(18), "Invalid _decimals");
        if (uint256(decimals) > paymentToken.decimals()) {
            return price / (10 ** (uint256(decimals) - paymentToken.decimals()));
        } else if (uint256(decimals) < paymentToken.decimals()) {
            return price * (10 ** (paymentToken.decimals() - uint256(decimals)));
        }
        return price;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256, //amountOutMin,
        address[] calldata path,
        address, //to,
        uint256 //deadline
    ) external returns (uint256[] memory amountsOut) {
        require(path.length == 2, "invalid path length");
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 amountOutMin = convertToDecimal(
            IERC20Metadata(path[1]),
            amountIn,
            IERC20Metadata(path[0]).decimals()
        );
        if (path[1] == address(DAI)) {
            DAIMint(address(DAI)).mint(amountOutMin);
        } else {
            USDMint(address(path[1])).mint(address(this), amountOutMin);
        }
        IERC20(path[1]).safeTransfer(msg.sender, amountOutMin);
        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        amountsOut[1] = amountOutMin;
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountIn,
        address[] calldata path,
        address, //to,
        uint256 //deadline
    ) external returns (uint256[] memory amountsOut) {
        require(path.length == 2, "invalid path length");
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        if (path[1] == address(DAI)) {
            DAIMint(address(DAI)).mint(amountOut);
        } else {
            USDMint(address(path[1])).mint(address(this), amountOut);
        }

        IERC20(path[1]).safeTransfer(msg.sender, amountOut);
        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        amountsOut[1] = amountOut;
    }
}
