// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

// local helper imports
import "./utils/stRWA.setUp.sol";

/**
 * @title StakedRWARebaseTest
 * @author @chasebrownn
 * @notice This test file contains unit tests for stRWA::rebase.
 */
contract StakedRWARebaseTest is Test, StakedRWATestUtility {
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

    /// @dev Builds swap data and calls tokenSilo::convertRewardToken to perform the ETH->RWA swap.
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

    /// @dev Utility function for performing rebase on stRWA. Performs state checks post-rebase.
    function _rebase() internal {
        uint256 balance = rwaToken.balanceOf(address(tokenSilo));
        uint256 preLocked = tokenSilo.getLockedAmount();
        uint256 preSupply = rwaToken.totalSupply();
        (uint256 burnAmount,,uint256 rebaseAmount) = tokenSilo.getAmounts(balance);

        vm.prank(MULTISIG);
        stRWA.rebase();

        // Verify amount burned and amount rebased is correct.
        assertEq(burnAmount, balance * 2 / 10);
        assertEq(rebaseAmount, balance * 8 / 10);
        // Verify tokenSilo has 0 RWA after rebase.
        assertApproxEqAbs(rwaToken.balanceOf(address(tokenSilo)), 0, 1);
        // Verify RWA supply and new locked amount post-rebase.
        assertEq(rwaToken.totalSupply(), preSupply - burnAmount);
        assertEq(tokenSilo.getLockedAmount(), preLocked + rebaseAmount);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies proper state changes when tokenSilo::claim is called.
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

    /// @dev Verifies proper state changes when tokenSilo::convertRewardToken is called.
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

    /// @dev Verifies proper state changes when stRWA::rebase is called.
    function test_stakedRWA_rebase_static() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        uint256 preSupply = stRWA.totalSupply();

        // ~ Execute rebase ~

        _rebase();

        assertEq(preSupply * stRWA.rebaseIndex() / 1e18, tokenSilo.getLockedAmount());
    }

    /// @dev Uses fuzzing to verify proper state changes when stRWA::rebase is called.
    function test_stakedRWA_rebase_fuzzing(uint256 amountRewards) public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        amountRewards = bound(amountRewards, .001 * 1e18, 100_000 * 1e18);
        deal(address(rwaToken), address(tokenSilo), amountRewards);

        // ~ Execute rebase ~

        _rebase();
    }

    /// @dev Uses fuzzing to verify proper state changes when there occurs a claim, convert, and rebase.
    function test_stakedRWA_claim_convert_rebase() public {
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

        // ~ State check 1 ~

        uint256 claimable = tokenSilo.claimable();
        emit log_named_uint("claimable ETH", claimable);
        assertGt(claimable, 0);

        uint256 preBalWETH = WETH.balanceOf(address(tokenSilo));

        // claim
        vm.prank(MULTISIG);
        uint256 claimed = tokenSilo.claim();

        // ~ State check 2

        assertEq(tokenSilo.claimable(), 0);
        assertEq(claimed, claimable);
        assertEq(WETH.balanceOf(address(tokenSilo)), preBalWETH + claimed);

        preBalWETH = WETH.balanceOf(address(tokenSilo));
        uint256 preBalRWA = rwaToken.balanceOf(address(tokenSilo));
        uint256 quote = _getQuote(claimed);

        // convert
        uint256 amountOut = _convertRewardToken(claimed);

        // ~ State check 3 ~

        assertEq(WETH.balanceOf(address(tokenSilo)), preBalWETH - claimed);
        assertEq(rwaToken.balanceOf(address(tokenSilo)), preBalRWA + quote);

        uint256 preLocked = tokenSilo.getLockedAmount();
        uint256 preSupply = rwaToken.totalSupply();

        (uint256 burnAmount,,uint256 rebaseAmount) = tokenSilo.getAmounts(amountOut);
        emit log_named_uint("burn amount", burnAmount);
        emit log_named_uint("rebase amount", rebaseAmount);

        assertEq(burnAmount, amountOut * 2 / 10);
        assertEq(rebaseAmount, amountOut * 8 / 10);

        // rebase
        vm.prank(MULTISIG);
        stRWA.rebase();

        // ~ State check 4 ~

        assertGt(stRWA.previewRedeem(stRWA.balanceOf(JOE)), amountTokens);
        assertEq(rwaToken.totalSupply(), preSupply - burnAmount);
        assertEq(tokenSilo.getLockedAmount(), preLocked + rebaseAmount);
    }

    /**
     * @dev Uses fuzzing to verify proper state changes when sequential rebases occur.
     *
     * rebase 1:
     * TS: 10,000
     * LO: 10,000 + 10,000
     * Increase of 100%
     * rebaseIndex = 2
     *
     * rebase 2:
     * TS: 20,000
     * LO: 20,000 + 10,000
     * Increase of 50%
     * rebaseIndex = 3
     */
    function test_stakedRWA_rebase_sequential_rebase_100() public {
        vm.prank(MULTISIG);
        tokenSilo.updateRatios(0, 0, 1);

        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        // ~ State check 1 ~

        assertEq(stRWA.rebaseIndex(), 1 * 1e18);
        assertEq(stRWA.balanceOf(JOE), amountTokens);

        // ~ rebase ~

        vm.prank(MULTISIG);
        stRWA.rebase();

        // ~ State check 2 ~

        assertEq(stRWA.rebaseIndex(), 2 * 1e18);
        assertEq(stRWA.balanceOf(JOE), amountTokens * stRWA.rebaseIndex() / 1e18);
        assertApproxEqAbs(stRWA.totalSupply(), tokenSilo.getLockedAmount(), 1);

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        // ~ rebase ~

        vm.prank(MULTISIG);
        stRWA.rebase();

        // ~ State check 3 ~

        assertEq(stRWA.rebaseIndex(), 3 * 1e18);
        assertEq(stRWA.balanceOf(JOE), amountTokens * stRWA.rebaseIndex() / 1e18);
        assertApproxEqAbs(stRWA.totalSupply(), tokenSilo.getLockedAmount(), 1);
    }

    /// @dev Uses fuzzing to verify proper state changes when sequential rebases occur.
    function test_stakedRWA_rebase_sequential_rebase_80() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        // ~ State check 1 ~

        assertEq(stRWA.rebaseIndex(), 1 * 1e18);
        assertEq(stRWA.balanceOf(JOE), amountTokens);

        // ~ rebase ~

        vm.prank(MULTISIG);
        stRWA.rebase();

        // ~ State check 2 ~

        assertEq(stRWA.rebaseIndex(), 1.8 * 1e18);
        assertEq(stRWA.balanceOf(JOE), amountTokens * stRWA.rebaseIndex() / 1e18);
        assertApproxEqAbs(stRWA.totalSupply(), tokenSilo.getLockedAmount(), 1);

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        // ~ rebase ~

        vm.prank(MULTISIG);
        stRWA.rebase();

        // ~ State check 3 ~

        assertApproxEqAbs(stRWA.rebaseIndex(), 2.6 * 1e18, 1);
        assertApproxEqAbs(stRWA.balanceOf(JOE), amountTokens * stRWA.rebaseIndex() / 1e18, 1);
        assertApproxEqAbs(stRWA.totalSupply(), tokenSilo.getLockedAmount(), 10000);
    }

    /// @dev Verifies proper state changes when a redemption occurs following a rebase.
    function test_stakedRWA_rebase_redeem() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        uint256 preSupply = stRWA.totalSupply();

        // ~ Execute rebase ~

        _rebase();

        // ~ Execute redemption ~

        uint256 bal = stRWA.balanceOf(JOE);
        vm.prank(JOE);
        stRWA.redeem(bal, JOE, JOE);

        // ~ State check ~

        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);
        
        assertEq(rwaVotingEscrow.balanceOf(JOE), 1);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), bal);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);
        assertEq(tokenSilo.getLockedAmount(), 0);
    }

    /// @dev Verifies proper state changes when a redemption occurs following a rebase.
    function test_stakedRWA_rebase_redeem_fee() public {
        // ~ Config ~

        vm.prank(MULTISIG);
        tokenSilo.setFee(350);

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        uint256 preSupply = stRWA.totalSupply();

        // ~ Execute rebase ~

        _rebase();

        // ~ Execute redemption ~

        uint256 bal = stRWA.balanceOf(JOE);
        uint256 fee = bal * tokenSilo.fee() / 100_00;
        vm.prank(JOE);
        stRWA.redeem(bal, JOE, JOE);

        // ~ State check ~

        assertEq(stRWA.balanceOf(JOE), 0);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), fee);
        
        assertEq(rwaVotingEscrow.balanceOf(JOE), 1);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), bal - fee);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), fee);
        assertEq(tokenSilo.getLockedAmount(), fee);
    }
}