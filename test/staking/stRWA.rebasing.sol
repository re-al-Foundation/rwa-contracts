// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

// local helper imports
import "./utils/stRWA.setUp.sol";

/**
 * @title StakedRWATest
 * @author @chasebrownn
 * @notice TODO
 */
contract StakedRWATest is Test, StakedRWATestUtility {
    function setUp() public override {
        super.setUp();
    }


    // -------
    // Utility
    // -------

    /// @dev Returns the amount of ETH quoted for `amount` $RWA.
    function _getQuote(uint256 amount) internal returns (uint256) {
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(rwaToken),
            amountIn: amount,
            fee: 3000,
            sqrtPriceLimitX96: 0
        });

        (uint256 amountOut,,,) = quoter.quoteExactInputSingle(params);
        return amountOut;
    }

    function _convertRewardToken(uint256 amount) internal returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(rwaToken),
            fee: 3000,
            recipient: address(tokenSilo),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data = 
            abi.encodeWithSignature(
                "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                params.tokenIn,
                params.tokenOut,
                params.fee,
                params.recipient,
                params.deadline,
                params.amountIn,
                params.amountOutMinimum,
                params.sqrtPriceLimitX96
            );

        vm.prank(MULTISIG);
        return tokenSilo.convertRewardToken(
            address(0),
            amount,
            address(router),
            data
        );
    }


    // ----------
    // Unit Tests
    // ----------

    function test_stakedRWA_claim() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // emulate rewards
        vm.deal(address(revDist), 10 ether);
        vm.prank(MULTISIG);
        revDist.distributeETH();
        skip(1);

        // ~ Pre-state check ~

        uint256 claimable = tokenSilo.claimable();
        emit log_named_uint("claimable ETH", claimable);
        assertGt(claimable, 0);

        uint256 preBal = WETH.balanceOf(address(tokenSilo));

        // ~ claim ~

        vm.prank(MULTISIG);
        tokenSilo.claim();

        // ~ Post-state check ~

        assertEq(tokenSilo.claimable(), 0);
        assertEq(WETH.balanceOf(address(tokenSilo)), preBal + claimable);
    }

    function test_stakedRWA_convertRewardToken() public {
        // ~ Config ~

        uint256 amountETH = 10 ether;
        deal(address(WETH), address(tokenSilo), amountETH);

        uint256 preBalWETH = WETH.balanceOf(address(tokenSilo));
        uint256 preBalRWA = rwaToken.balanceOf(address(tokenSilo));
        uint256 quote = _getQuote(amountETH);

        // ~ Execute 

        _convertRewardToken(amountETH);

        // ~ Post-state check ~

        assertEq(WETH.balanceOf(address(tokenSilo)), preBalWETH - amountETH);
        assertEq(rwaToken.balanceOf(address(tokenSilo)), preBalRWA + quote);
    }

    function test_stakedRWA_rebase() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        // ~ Pre-state check ~

        uint256 preLocked = tokenSilo.getLockedAmount();
        uint256 preSupply = rwaToken.totalSupply();

        (uint256 burnAmount,,uint256 rebaseAmount) = tokenSilo.getAmounts(amountTokens);
        emit log_named_uint("burn amount", burnAmount);
        emit log_named_uint("rebase amount", rebaseAmount);

        assertEq(burnAmount, amountTokens * 2 / 10);
        assertEq(rebaseAmount, amountTokens * 8 / 10);

        // ~ rebase ~

        vm.prank(MULTISIG);
        stRWA.rebase();

        // ~ Post-state check ~

        assertGt(stRWA.previewRedeem(stRWA.balanceOf(JOE)), amountTokens);

        assertEq(rwaToken.totalSupply(), preSupply - burnAmount);
        assertEq(tokenSilo.getLockedAmount(), preLocked + rebaseAmount);
    }

    function test_stakedRWA_claim_convert_rebase() public {

    }

    function test_stakedRWA_rebase_sequential() public {

    }

    function test_stakedRWA_rebase_redeem() public {
        // TODO
    }
}