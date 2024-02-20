// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import { IWETH } from "../interfaces/IWETH.sol";

contract ExactInputWrapper {

    ISwapRouter public swapRouter;
    IWETH public WETH;

    constructor(address _router, address _weth) {
        swapRouter = ISwapRouter(_router);
        WETH = IWETH(_weth);
    }

    receive() external payable {}

    function exactInputForETH(
        bytes memory path,
        address tokenIn,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut) {

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin
        });
        uint256 preBal = IERC20(WETH).balanceOf(address(this));

        IERC20(address(tokenIn)).transferFrom(msg.sender, address(this), amountIn);
        IERC20(address(tokenIn)).approve(address(swapRouter), amountIn);
        amountOut = swapRouter.exactInput(params);

        require(amountOut != 0, "Insufficient amount out");

        uint256 postBal = IERC20(WETH).balanceOf(address(this));
        require(postBal == preBal + amountOut , "WETH balance did not increase");

        WETH.withdraw(amountOut);

        (bool success,) = recipient.call{value:amountOut}("");
        require(success, "transfer of ETH failed");
    }
}