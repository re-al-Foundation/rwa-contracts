// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import { IWETH } from "../interfaces/IWETH.sol";

contract ExactInputWrapper is Ownable {

    ISwapRouter public swapRouter;
    IWETH public immutable WETH;

    constructor(address _router, address _weth) Ownable(msg.sender) {
        swapRouter = ISwapRouter(_router);
        WETH = IWETH(_weth);
    }

    receive() external payable {
        require(msg.sender == address(swapRouter) || msg.sender == address(WETH), "NA");
    }

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
        amountOut = swapRouter.exactInputFeeOnTransfer(params);
        //amountOut = swapRouter.exactInput(params);

        require(amountOut != 0, "Insufficient amount out");

        uint256 postBal = IERC20(WETH).balanceOf(address(this));
        require(postBal == preBal + amountOut , "WETH balance did not increase");

        WETH.withdraw(amountOut);

        (bool success,) = recipient.call{value:amountOut}("");
        require(success, "transfer of ETH failed");
    }

    function updateSwapRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid address");
        swapRouter = ISwapRouter(_router);
    }
}