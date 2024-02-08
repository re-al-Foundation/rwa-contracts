// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// local imports
import { RevenueStream } from "../src/RevenueStream.sol";
import { RevenueDistributor } from "../src/RevenueDistributor.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { DelegateFactory } from "../src/governance/DelegateFactory.sol";
import { Delegator } from "../src/governance/Delegator.sol";

// local helper imports
import { Utility } from "./utils/Utility.sol";
import "./utils/Constants.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Router01 } from "../src/interfaces/IUniswapV2Router01.sol";
import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "../src/interfaces/IUniswapV2Factory.sol";

/**
 * @title RWATokenTest
 * @author @chasebrownn
 * @notice Contains unit tests for $RWA token. Tests focus on transaction taxes.
 */
contract RWATokenTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    RevenueStream public revStream;
    RevenueDistributor public revDistributor;
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    DelegateFactory public delegateFactory;
    Delegator public delegator;

    // proxies
    ERC1967Proxy public revStreamProxy;
    ERC1967Proxy public revDistributorProxy;
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public delegateFactoryProxy;

    // ~ Variables ~

    address public WETH;

    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        WETH = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();

        // ~ $RWA Deployment ~

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN,
                MUMBAI_UNIV2_ROUTER,
                address(0)
            )
        );
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));

        // ~ Vesting Deployment ~

        // Deploy vesting contract
        vesting = new VotingEscrowVesting();

        // Deploy proxy for vesting contract
        vestingProxy = new ERC1967Proxy(
            address(vesting),
            abi.encodeWithSelector(VotingEscrowVesting.initialize.selector,
                ADMIN
            )
        );
        vesting = VotingEscrowVesting(address(vestingProxy));


        // ~ veRWA Deployment ~

        // Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();

        // Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken),
                address(vesting),
                LAYER_Z, // Note: Layer Zero Endpoint -> For migration
                ADMIN
            )
        );
        veRWA = RWAVotingEscrow(address(veRWAProxy));


        // ~ Revenue Distributor Deployment ~

        // Deploy base contract for beacon
        revStream = new RevenueStream();

        // Deploy revDistributor contract
        revDistributor = new RevenueDistributor();

        // Deploy proxy for revDistributor
        revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                ADMIN,
                address(revStream),
                address(veRWA)
            )
        );
        revDistributor = RevenueDistributor(payable(address(revDistributorProxy)));


        // ~ Delegator Deployment ~

        // Deploy Delegator implementation
        delegator = new Delegator();

        // Deploy DelegateFactory
        delegateFactory = new DelegateFactory();

        // Deploy DelegateFactory proxy
        delegateFactoryProxy = new ERC1967Proxy(
            address(delegateFactory),
            abi.encodeWithSelector(DelegateFactory.initialize.selector,
                address(veRWA),
                address(delegator),
                ADMIN
            )
        );
        delegateFactory = DelegateFactory(address(delegateFactoryProxy));


        // ~ Config ~

        // vm.prank(ADMIN);
        // revStream = RevenueStream(revDistributor.createNewRevStream(address(rwaToken)));

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        vm.prank(ADMIN);
        rwaToken.setRevenueDistributor(address(revDistributor));

        // create pair
        address pair = IUniswapV2Factory(IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).factory()).createPair(address(rwaToken), WETH);

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.setUniswapV2Pair(pair);
        rwaToken.grantRole(MINTER_ROLE, address(this)); // for testing
        rwaToken.grantRole(BURNER_ROLE, address(this)); // for testing
        rwaToken.grantRole(MINTER_ROLE, address(veRWA)); // for RWAVotingEscrow:migrate
        rwaToken.grantRole(BURNER_ROLE, address(veRWA)); // for RWAVotingEscrow:migrate
        // whitelist
        rwaToken.excludeFromFees(address(veRWA), true);
        vm.stopPrank();

        // Mint Joe $RWA tokens
        //rwaToken.mintFor(JOE, 1_000 ether);


        // ~ Create LP for $RWA Token ~

        uint256 ETH_DEPOSIT = 10 ether;
        uint256 TOKEN_DEPOSIT = 1_000_000 ether;

        rwaToken.mint(TOKEN_DEPOSIT);
        rwaToken.approve(address(MUMBAI_UNIV2_ROUTER), TOKEN_DEPOSIT);

        // Create liquidity pool.
        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).addLiquidityETH{value: ETH_DEPOSIT}(
            address(rwaToken),
            TOKEN_DEPOSIT,
            TOKEN_DEPOSIT,
            ETH_DEPOSIT,
            address(this),
            block.timestamp + 300
        );

        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(rwaToken.uniswapV2Pair()).getReserves();
        emit log_named_uint("RWA Init Reserves", reserve0);
        emit log_named_uint("ETH Init Reserves", reserve1);

        vm.prank(address(rwaToken));
        rwaToken.approve(address(this), TOKEN_DEPOSIT - reserve0);
        rwaToken.burnFrom(address(rwaToken), TOKEN_DEPOSIT - reserve0);
    }


    // -------
    // Utility
    // -------

    /// @dev Returns the amount of $RWA tokens quoted for `amount` ETH.
    function _getQuoteBuy(uint256 amount) internal returns (uint256) {
        address[] memory path = new address[](2);

        path[0] = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();
        path[1] = address(rwaToken);

        uint256[] memory amounts = IUniswapV2Router01(MUMBAI_UNIV2_ROUTER).getAmountsOut(amount, path);
        return amounts[1];
    }

    /// @dev Perform a buy
    function _buy(address actor, uint256 amount) internal {
        address[] memory path = new address[](2);

        path[0] = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();
        path[1] = address(rwaToken);

        vm.startPrank(actor);
        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            actor,
            block.timestamp + 300
        );
        vm.stopPrank();
    }

    /// @dev Returns the amount of ETH quoted for `amount` $RWA.
    function _getQuoteSell(uint256 amount) internal returns (uint256) {
        address[] memory path = new address[](2);

        path[0] = address(rwaToken);
        path[1] = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();

        uint256[] memory amounts = IUniswapV2Router01(MUMBAI_UNIV2_ROUTER).getAmountsOut(amount, path);
        return amounts[1];
    }

    /// @dev Perform a sell
    function _sell(address actor, uint256 amount) internal {
        address[] memory path = new address[](2);

        path[0] = address(rwaToken);
        path[1] = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();

        vm.startPrank(actor);
        rwaToken.approve(MUMBAI_UNIV2_ROUTER, amount);
        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            actor,
            block.timestamp + 300
        );
        vm.stopPrank();
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @dev Verifies initial state of RWAToken contract.
    function test_rwaToken_init_state() public {
        assertNotEq(rwaToken.uniswapV2Pair(), address(0));
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies proper state changes when a user buys $RWA tokens from a UniV2Pool.
    function test_rwaToken_buy() public {

        // ~ Config ~

        uint256 amountETH = 1 ether;
        vm.deal(JOE, amountETH);

        // get quote for buy
        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        // ~ Pre-state check ~

        assertEq(JOE.balance, amountETH);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute buy ~

        _buy(JOE, amountETH);

        // ~ Post-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), quote - taxedAmount);
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
    }

    /// @dev Verifies proper state changes when a WHITELISTED user buys $RWA tokens from a UniV2Pool.
    ///      A tax will not be taken from user during buy.
    function test_rwaToken_buy_WL() public {

        // ~ Config ~

        vm.prank(ADMIN);
        rwaToken.excludeFromFees(JOE, true);

        uint256 amountETH = 1 ether;
        vm.deal(JOE, amountETH);

        // get quote for buy
        uint256 quote = _getQuoteBuy(amountETH);

        // ~ Pre-state check ~

        assertEq(JOE.balance, amountETH);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute buy ~

        _buy(JOE, amountETH);

        // ~ Post-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), quote);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }

    /// @dev Uses fuzzing to verify proper state changes when a user buys $RWA tokens from a UniV2Pool.
    function test_rwaToken_buy_fuzzing(uint256 amountETH) public {
        amountETH = bound(amountETH, 100, 1_000 ether); // Range 0.000000000000001 -> 1,000

        // ~ Config ~

        vm.deal(JOE, amountETH);

        // get quote for buy
        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        // ~ Pre-state check ~

        assertEq(JOE.balance, amountETH);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute buy ~

        _buy(JOE, amountETH);

        // ~ Post-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), quote - taxedAmount);
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
    }

    /// @dev Verifies proper state changes when a user sells $RWA tokens into a UniV2Pool.
    function test_rwaToken_sell() public {

        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        // get quote for buy
        uint256 quote = _getQuoteSell(amountTokens);
        uint256 taxedAmount = amountTokens * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute sell ~

        _sell(JOE, amountTokens);

        // ~ Post-state check

        assertGt(JOE.balance, 0);
        assertLt(JOE.balance, quote);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
    }

    /// @dev Verifies proper state changes when a WHITELISTED user sells $RWA tokens into a UniV2Pool.
    ///      A tax will not be taken from whitelisted user during sell.
    function test_rwaToken_sell_WL() public {

        // ~ Config ~

        vm.prank(ADMIN);
        rwaToken.excludeFromFees(JOE, true);

        uint256 amountTokens = 10_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        // get quote for buy
        uint256 quote = _getQuoteSell(amountTokens);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute sell ~

        _sell(JOE, amountTokens);

        // ~ Post-state check

        assertEq(JOE.balance, quote); // no tax taken.
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }

    /// @dev Uses fuzzing to verify proper state changes when a user sells $RWA tokens into a UniV2Pool.
    function test_rwaToken_sell_fuzzing(uint256 amountTokens) public {
        amountTokens = bound(amountTokens, 0.000000001 ether, 500_000 ether); // Range 0.000000001 -> 500k tokens

        // ~ Config ~

        rwaToken.mintFor(JOE, amountTokens);

        // get quote for buy
        uint256 quote = _getQuoteSell(amountTokens);
        uint256 taxedAmount = amountTokens * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute sell ~

        _sell(JOE, amountTokens);

        // ~ Post-state check

        assertGt(JOE.balance, 0);
        assertLt(JOE.balance, quote);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
    }

    /// @dev Verifies proper state changes when a user transfer tokens to another user.
    ///      Normal pier to pier transfers will result in 0 tax.
    function test_rwaToken_transfer() public {

        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute transfer ~

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        // ~ Post-state check

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }

    /// @dev Verifies proper state changes when a user transfer tokens to another user.
    ///      Normal pier to pier transfers will result in 0 tax.
    ///      Whitelisted users also receive no tax on transfer.
    function test_rwaToken_transfer_WL() public {

        // ~ Config ~

        vm.prank(ADMIN);
        rwaToken.excludeFromFees(JOE, true);

        uint256 amountTokens = 10_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute transfer ~

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        // ~ Post-state check

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }

    /// @dev Uses fuzzing to verify proper state changes when a user transfer tokens to another user.
    ///      Normal pier to pier transfers will result in 0 tax.
    function test_rwaToken_transfer_fuzzing(uint256 amountTokens) public {
        amountTokens = bound(amountTokens, 0.000000001 ether, 500_000 ether); // Range 0.000000001 -> 500k tokens

        // ~ Config ~

        rwaToken.mintFor(JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute transfer ~

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        // ~ Post-state check

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }

    /// @dev Verifies proper state changes when there are accumulated fees on the RWA contract and
    ///      there is a second buy that occurs without distributing royalties.
    function test_rwaToken_royaltyDistribution_onBuy() public {

        // ~ Config ~

        uint256 amountETH = 10 ether;
        vm.deal(JOE, amountETH);

        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        uint256 preSupply = rwaToken.totalSupply();

        // Execute buy to accumulate fees
        _buy(JOE, amountETH);

        // ~ Pre-state check ~
    
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);
        assertEq(rwaToken.totalSupply(), preSupply);

        (uint256 preReserve0, uint256 preReserve1,) = IUniswapV2Pair(rwaToken.uniswapV2Pair()).getReserves();
        emit log_named_uint("RWA PRE BUY Reserves", preReserve0);
        emit log_named_uint("ETH PRE BUY Reserves", preReserve1);

        quote = _getQuoteBuy(amountETH);

        // ~ Execute buy -> Royalties do NOT distribute ~

        vm.deal(JOE, amountETH);
        _buy(JOE, amountETH);

        // ~ Post-state check ~
    
        assertGt(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);
        assertEq(rwaToken.totalSupply(), preSupply);

        (uint256 postReserve0, uint256 postReserve1,) = IUniswapV2Pair(rwaToken.uniswapV2Pair()).getReserves();
        emit log_named_uint("RWA POST BUY Reserves", postReserve0); // DOWN
        emit log_named_uint("ETH POST BUY Reserves", postReserve1); // UP

        assertEq(postReserve0, preReserve0 - quote);
        assertEq(postReserve1, preReserve1 + amountETH);
    }

    /// @dev Verifies proper state changes when there are accumulated fees on the RWA contract and
    ///      there is a sequential sell that occurs distributing royalties.
    function test_rwaToken_royaltyDistribution_onSell() public {

        // ~ Config ~

        uint256 amountETH = 10 ether;
        vm.deal(JOE, amountETH);

        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        uint256 burnPortion = (taxedAmount * rwaToken.burnFee()) / rwaToken.totalFees(); // 2/5
        emit log_named_uint("burn portion", burnPortion);

        uint256 revSharePortion = (taxedAmount * rwaToken.revShareFee()) / rwaToken.totalFees(); // 2/5
        emit log_named_uint("revDistributor portion", revSharePortion);

        uint256 lpPortion = taxedAmount - burnPortion - revSharePortion; // 1/5
        emit log_named_uint("lp portion", lpPortion);

        uint256 tokensForEthLp = lpPortion/2;
        lpPortion -= lpPortion;

        uint256 preSupply = rwaToken.totalSupply();

        // Execute buy to accumulate fees
        _buy(JOE, amountETH);

        // ~ Pre-state check ~
    
        assertEq(rwaToken.balanceOf(JOE), quote - taxedAmount);
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
        
        assertEq(rwaToken.totalSupply(), preSupply);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        // ~ Execute sell -> distribute ~

        uint256 amountToSell = 1_000 ether;
        _sell(JOE, amountToSell);

        // ~ Post-state check ~
    
        assertEq(rwaToken.balanceOf(address(rwaToken)), amountToSell * rwaToken.totalFees() / 100);

        assertEq(rwaToken.totalSupply(), preSupply - burnPortion);
        assertEq(rwaToken.balanceOf(address(revDistributor)), revSharePortion);
    }

    /// @dev Verifies proper state changes when there are accumulated fees on the RWA contract and
    ///      there is a sequential transfer that occurs distributing royalties.
    function test_rwaToken_royaltyDistribution_onTransfer() public {

        // ~ Config ~

        uint256 amountETH = 10 ether;
        vm.deal(JOE, amountETH);

        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        uint256 burnPortion = (taxedAmount * rwaToken.burnFee()) / rwaToken.totalFees(); // 2/5
        uint256 revSharePortion = (taxedAmount * rwaToken.revShareFee()) / rwaToken.totalFees(); // 2/5

        uint256 preSupply = rwaToken.totalSupply();

        // Execute buy to accumulate fees
        _buy(JOE, amountETH);

        // ~ Pre-state check ~
    
        assertEq(rwaToken.balanceOf(JOE), quote - taxedAmount);
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
        
        assertEq(rwaToken.totalSupply(), preSupply);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        (uint256 preReserve0, uint256 preReserve1,) = IUniswapV2Pair(rwaToken.uniswapV2Pair()).getReserves();
        emit log_named_uint("RWA PRE TRANSFER Reserves", preReserve0);
        emit log_named_uint("ETH PRE TRANSFER Reserves", preReserve1);

        // ~ Execute transfer -> distribute ~

        uint256 amountToTransfer = 1_000 ether;
        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountToTransfer); 

        // ~ Post-state check ~
    
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0); // NOTE NO TAX ON TRANSFER

        assertEq(rwaToken.totalSupply(), preSupply - burnPortion);
        assertEq(rwaToken.balanceOf(address(revDistributor)), revSharePortion);

        (uint256 postReserve0, uint256 postReserve1,) = IUniswapV2Pair(rwaToken.uniswapV2Pair()).getReserves();
        emit log_named_uint("RWA POST TRANSFER Reserves", postReserve0);
        emit log_named_uint("ETH POST TRANSFER Reserves", postReserve1);

        assertGt(postReserve0, preReserve0);
    }

    /// @dev Verifies proper state changes when updateFees is executed.
    function test_rwaToken_updateFees() public {

        // ~ Pre-state check ~

        assertEq(rwaToken.burnFee(), 2);
        assertEq(rwaToken.revShareFee(), 2);
        assertEq(rwaToken.lpFee(), 1);
        assertEq(rwaToken.totalFees(), 5);

        // ~ Execute updateFees ~

        vm.prank(ADMIN);
        rwaToken.updateFees(4, 4, 2);

        // ~ Post-state check ~

        assertEq(rwaToken.burnFee(), 4);
        assertEq(rwaToken.revShareFee(), 4);
        assertEq(rwaToken.lpFee(), 2);
        assertEq(rwaToken.totalFees(), 10);
    }

    /// @dev Verifies proper taxation and distribution after fees have been modified.
    function test_rwaToken_updateFees_royaltyDistribution() public {

        // ~ Config ~

        uint256 amountETH = 10 ether;
        vm.deal(JOE, amountETH);

        vm.prank(ADMIN);
        rwaToken.updateFees(4, 4, 2);

        assertEq(rwaToken.burnFee(), 4);
        assertEq(rwaToken.revShareFee(), 4);
        assertEq(rwaToken.lpFee(), 2);
        assertEq(rwaToken.totalFees(), 10);

        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.totalFees() / 100;
        assertGt(taxedAmount, 0);

        uint256 burnPortion = (taxedAmount * rwaToken.burnFee()) / rwaToken.totalFees(); // 4/10
        uint256 revSharePortion = (taxedAmount * rwaToken.revShareFee()) / rwaToken.totalFees(); // 4/10

        uint256 preSupply = rwaToken.totalSupply();

        // Execute buy to accumulate fees
        _buy(JOE, amountETH);

        // ~ Pre-state check ~
    
        assertEq(rwaToken.balanceOf(JOE), quote - taxedAmount);
        assertEq(rwaToken.balanceOf(address(rwaToken)), taxedAmount);
        
        assertEq(rwaToken.totalSupply(), preSupply);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        (uint256 preReserve0, uint256 preReserve1,) = IUniswapV2Pair(rwaToken.uniswapV2Pair()).getReserves();
        emit log_named_uint("RWA PRE TRANSFER Reserves", preReserve0);
        emit log_named_uint("ETH PRE TRANSFER Reserves", preReserve1);

        // ~ Execute transfer -> distribute ~

        uint256 amountToTransfer = 1_000 ether;
        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountToTransfer); 

        // ~ Post-state check ~
    
        //assertEq(rwaToken.balanceOf(address(rwaToken)), (amountToTransfer * rwaToken.totalFees()) / 100);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0); // NOTE NO TAX ON TRANSFER

        assertEq(rwaToken.totalSupply(), preSupply - burnPortion);
        assertEq(rwaToken.balanceOf(address(revDistributor)), revSharePortion);

        (uint256 postReserve0, uint256 postReserve1,) = IUniswapV2Pair(rwaToken.uniswapV2Pair()).getReserves();
        emit log_named_uint("RWA POST TRANSFER Reserves", postReserve0);
        emit log_named_uint("ETH POST TRANSFER Reserves", postReserve1);

        assertGt(postReserve0, preReserve0);
    }

    function test_rwaToken_blacklist() public {

        vm.prank(ADMIN);
        rwaToken.modifyBlacklist(JOE, true);

        // mint RWA for sell
        uint256 amountTokens = 10_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        // mint ETH for buy
        uint256 amountETH = 1 ether;
        vm.deal(JOE, amountETH);

        assertEq(rwaToken.isBlacklisted(JOE), true);

        // buy -> revert

        address[] memory path = new address[](2);

        path[0] = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();
        path[1] = address(rwaToken);

        vm.startPrank(JOE);
        vm.expectRevert();
        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountETH}(
            0,
            path,
            JOE,
            block.timestamp + 300
        );
        vm.stopPrank();

        // sell -> revert

        path[0] = address(rwaToken);
        path[1] = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();

        vm.startPrank(JOE);
        rwaToken.approve(MUMBAI_UNIV2_ROUTER, amountTokens);
        vm.expectRevert();
        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountTokens,
            0,
            path,
            JOE,
            block.timestamp + 300
        );
        vm.stopPrank();

        // transfer -> revert

        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.Blacklisted.selector, JOE));
        rwaToken.transfer(ALICE, amountTokens);

        // Whitelist Alice then transfer from Joe -> success

        vm.prank(ADMIN);
        rwaToken.excludeFromFees(ALICE, true);

        assertEq(rwaToken.isExcludedFromFees(ALICE), true);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(JOE), amountTokens);

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        assertEq(rwaToken.balanceOf(ALICE), amountTokens);
        assertEq(rwaToken.balanceOf(JOE), 0);
    }
}