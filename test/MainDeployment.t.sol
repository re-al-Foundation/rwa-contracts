// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

// passive income nft imports
import { PassiveIncomeNFT } from "../src/refs/PassiveIncomeNFT.sol";

// layerZero imports
import { ILayerZeroEndpoint } from "@layerZero/contracts/interfaces/ILayerZeroEndpoint.sol";

// local imports
import { CrossChainMigrator } from "../src/CrossChainMigrator.sol";
import { RevenueDistributor } from "../src/RevenueDistributor.sol";
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
import { RealReceiver } from "../src/RealReceiver.sol";
import { TangibleERC20Mock } from "./utils/TangibleERC20Mock.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { RoyaltyHandler } from "../src/RoyaltyHandler.sol";
import { LZEndpointMock } from "./utils/LZEndpointMock.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import { DelegateFactory } from "../src/governance/DelegateFactory.sol";
import { Delegator } from "../src/governance/Delegator.sol";

import { VotingEscrowRWAAPI } from "../src/helpers/VotingEscrowRWAAPI.sol";

import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV3Factory } from "../src/interfaces/IUniswapV3Factory.sol";
import { IUniswapV2Factory } from "../src/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
import { IPearlV2PoolFactory } from "../src/interfaces/IPearlV2PoolFactory.sol";
import { ISwapRouter } from "./interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "./interfaces/IQuoterV2.sol";

import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

// helper
import { ExactInputWrapper } from "../src/helpers/ExactInputWrapper.sol";

// local helper imports
import "./utils/Utility.sol";
import "./utils/Constants.sol";

/**
 * @title MainDeploymentTest
 * @author @chasebrownn
 * @notice This test file contains the basic integration testing for migration contracts.
 */
contract MainDeploymentTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    // PassiveIncomeNFT public passiveIncomeNFTV1 = PassiveIncomeNFT(POLYGON_PI_NFT);
    // TangibleERC20Mock public tngblToken = TangibleERC20Mock(POLYGON_TNGBL_TOKEN);
    RevenueDistributor public revDistributor;
    RevenueStreamETH public revStreamETH;
    RealReceiver public receiver;
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    RoyaltyHandler public royaltyHandler;
    DelegateFactory public delegateFactory;
    Delegator public delegator;
    VotingEscrowRWAAPI public api;

    // helper
    LZEndpointMock public endpoint;
    ExactInputWrapper public exactInputWrapper;

    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public royaltyHandlerProxy;
    ERC1967Proxy public migratorProxy;
    ERC1967Proxy public revDistributorProxy;
    ERC1967Proxy public receiverProxy;
    ERC1967Proxy public revStreamETHProxy;
    ERC1967Proxy public delegateFactoryProxy;
    ERC1967Proxy public apiProxy;

    // ~ Variables ~

    address public WETH;
    address public UNREAL_PAIR_MANAGER = 0x63Cd04630E9C6eCa572Fd39863B63ce6117eC86b;

    address public pair;

    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(UNREAL_UNIV2_ROUTER);
    IQuoterV2 public quoter = IQuoterV2(UNREAL_QUOTERV2);
    ISwapRouter public router = ISwapRouter(UNREAL_SWAP_ROUTER);

    IQuoterV2 public quoter_2 = IQuoterV2(UNREAL_QUOTERV2_NEW);
    ISwapRouter public router_2 = ISwapRouter(UNREAL_SWAP_ROUTER_NEW);

    address public UNREAL_ENDPOINT = address(bytes20(bytes("UNREAL ENDPOINT"))); // TODO: Replace

    bytes4 public selector_swapExactTokensForETH =
        bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));

    bytes4 public selector_universalRouterExecute = bytes4(keccak256("execute(bytes,bytes[])"));

    bytes4 public selector_exactInput = 
        //bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
        bytes4(keccak256("multicall(bytes[])"));

    bytes4 public selector_exactInputWrapper = 
        bytes4(keccak256("exactInputForETH(bytes,address,address,uint256,uint256,uint256)"));

    //address public ADMIN; // TODO: Assign address to admin

    function setUp() public {

        vm.createSelectFork(UNREAL_RPC_URL);

        WETH = uniswapV2Router.WETH();

        // ~ Deploy Contracts ~

        // (1) Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // (2) Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN
            )
        );
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));

        // (3) Deploy vesting contract
        vesting = new VotingEscrowVesting();

        // (4) Deploy proxy for vesting contract
        vestingProxy = new ERC1967Proxy(
            address(vesting),
            abi.encodeWithSelector(VotingEscrowVesting.initialize.selector,
                ADMIN // admin address
            )
        );
        vesting = VotingEscrowVesting(address(vestingProxy));

        // (5) Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();

        // (6) Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken), // RWA token
                address(vesting),  // votingEscrowVesting
                UNREAL_ENDPOINT, // LZ endpoint
                ADMIN // admin address
            )
        );
        veRWA = RWAVotingEscrow(address(veRWAProxy));

        // (7) Deploy RealReceiver
        receiver = new RealReceiver(address(endpoint));

        // (8) Deploy proxy for receiver
        receiverProxy = new ERC1967Proxy(
            address(receiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(block.chainid),
                address(veRWA),
                address(rwaToken),
                ADMIN
            )
        );
        receiver = RealReceiver(address(receiverProxy));

        // (9) Deploy revDistributor contract
        revDistributor = new RevenueDistributor();

        // (10) Deploy proxy for revDistributor
        revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                ADMIN,
                address(0),
                address(veRWA)
            )
        );
        revDistributor = RevenueDistributor(payable(address(revDistributorProxy)));

        // Deploy royaltyHandler base
        royaltyHandler = new RoyaltyHandler();

        // Deploy proxy for royaltyHandler
        royaltyHandlerProxy = new ERC1967Proxy(
            address(royaltyHandler),
            abi.encodeWithSelector(RoyaltyHandler.initialize.selector,
                ADMIN,
                address(revDistributor),
                address(rwaToken),
                address(uniswapV2Router)
            )
        );
        royaltyHandler = RoyaltyHandler(payable(address(royaltyHandlerProxy)));

        // (11) Deploy revStreamETH contract
        revStreamETH = new RevenueStreamETH();

        // (12) Deploy proxy for revStreamETH
        revStreamETHProxy = new ERC1967Proxy(
            address(revStreamETH),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                address(veRWA),
                ADMIN
            )
        );
        revStreamETH = RevenueStreamETH(payable(address(revStreamETHProxy)));

        // (13) Deploy Delegator implementation
        delegator = new Delegator();

        // (14) Deploy DelegateFactory
        delegateFactory = new DelegateFactory();

        // (15) Deploy DelegateFactory proxy
        delegateFactoryProxy = new ERC1967Proxy(
            address(delegateFactory),
            abi.encodeWithSelector(DelegateFactory.initialize.selector,
                address(veRWA),
                address(delegator),
                ADMIN
            )
        );
        delegateFactory = DelegateFactory(address(delegateFactoryProxy));

        // (16) Deploy API
        api = new VotingEscrowRWAAPI();

        // (17) Deploy api proxy
        apiProxy = new ERC1967Proxy(
            address(api),
            abi.encodeWithSelector(VotingEscrowRWAAPI.initialize.selector,
                ADMIN,
                address(veRWA),
                address(vesting),
                address(revStreamETH)
            )
        );
        api = VotingEscrowRWAAPI(address(apiProxy));

        // (18) Deploy wrapper
        exactInputWrapper = new ExactInputWrapper(address(UNREAL_SWAP_ROUTER), WETH);

        // ~ Config ~

        // (14) set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // (15) RevenueDistributor config
        vm.startPrank(ADMIN);
        // (15a) grant DISTRIBUTOR_ROLE to Gelato functions
        revDistributor.setDistributor(GELATO, true);
        // (15b) add revStream contract
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));
        // (15c) add revenue streams
        revDistributor.addRevenueToken(address(rwaToken)); // from RWA buy/sell taxes
        revDistributor.addRevenueToken(UNREAL_DAI); // DAI - bridge yield (ETH too)
        revDistributor.addRevenueToken(address(0)); // MORE - Borrowing fees (note not deployed)
        revDistributor.addRevenueToken(UNREAL_USTB); // USTB - caviar incentives, basket rent yield, marketplace fees
        // (15d) add necessary selectors for swaps
        revDistributor.setSelectorForTarget(UNREAL_UNIV2_ROUTER, selector_swapExactTokensForETH); // for RWA -> ETH swaps
        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInput); // for V3 swaps with swapRouter
        revDistributor.setSelectorForTarget(address(exactInputWrapper), selector_exactInputWrapper);
        revDistributor.setSelectorForTarget(address(router_2), selector_exactInput);
        vm.stopPrank();

        // (16) pair manager must create RWA/WETH pair
        vm.prank(UNREAL_PAIR_MANAGER);
        pair = IPearlV2PoolFactory(UNREAL_PEARLV2_FACTORY).createPool(address(rwaToken), WETH, 100);

        // (17) RWAToken config
        vm.startPrank(ADMIN);
        rwaToken.setRoyaltyHandler(address(royaltyHandler));
        // (17a) set uniswap pair
        rwaToken.setAutomatedMarketMakerPair(pair, true);
        // (17b) Grant roles
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(this)); // for testing
        // (17c) whitelist
        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(address(revDistributor), true);
        // (17d) set revenue distributor
        //rwaToken.setRevenueDistributor(address(revDistributor));
        vm.stopPrank();

        // ~ RWA/WETH Pool creation ~

        uint256 ETH_DEPOSIT = 15 ether;
        uint256 TOKEN_DEPOSIT = 16_500 ether;

        /// @dev https://blog.uniswap.org/uniswap-v3-math-primer

        uint256 initPrice = 2**96; // Q notation
        emit log_named_uint("init price", initPrice);

        // (address token0, address token1) = address(rwaToken) < WETH ? (address(rwaToken), WETH) : (WETH, address(rwaToken));
        // emit log_named_address("token0", token0);
        // emit log_named_address("token1", token1);

        IPearlV2PoolFactory(UNREAL_PEARLV2_FACTORY).initializePoolPrice(pair, uint160(initPrice));

        deal(WETH, address(this), ETH_DEPOSIT);
        IERC20(WETH).approve(UNREAL_NFTMANAGER, ETH_DEPOSIT);

        //rwaToken.mint(TOKEN_DEPOSIT);
        rwaToken.mintFor(address(this), TOKEN_DEPOSIT);
        rwaToken.approve(UNREAL_NFTMANAGER, TOKEN_DEPOSIT);

        // create params for LP mint
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(rwaToken),
            token1: WETH,
            fee: 100,
            tickLower: -100,
            tickUpper: 100,
            amount0Desired: TOKEN_DEPOSIT,
            amount1Desired: ETH_DEPOSIT,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        INonfungiblePositionManager(UNREAL_NFTMANAGER).mint(params);

        // (18) Create liquidity pool. TODO: Figure out desired ratio
        // uniswapV2Router.addLiquidityETH{value: ETH_DEPOSIT}(
        //     address(rwaToken),
        //     TOKEN_DEPOSIT,
        //     TOKEN_DEPOSIT,
        //     ETH_DEPOSIT,
        //     address(this),
        //     block.timestamp + 300
        // );

        // (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        // emit log_named_uint("RWA Init Reserves", reserve0);
        // emit log_named_uint("ETH Init Reserves", reserve1);

        // vm.prank(address(rwaToken));
        // rwaToken.approve(address(this), TOKEN_DEPOSIT - reserve0);
        // rwaToken.burnFrom(address(rwaToken), TOKEN_DEPOSIT - reserve0);

        // ~ note For testing, make USTB/WETH pool ~

        ETH_DEPOSIT = 10 ether;
        TOKEN_DEPOSIT = 20_000 ether;
                
        vm.prank(0x95e3664633A8650CaCD2c80A0F04fb56F65DF300); // USTB holder
        IERC20(address(UNREAL_USTB)).transfer(address(this), TOKEN_DEPOSIT);
        //deal(address(UNREAL_USTB), address(this), TOKEN_DEPOSIT);
        IERC20(address(UNREAL_USTB)).approve(address(UNREAL_UNIV2_ROUTER), TOKEN_DEPOSIT);

        vm.startPrank(UNREAL_PAIR_MANAGER);
        IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(UNREAL_USTB), WETH);
        vm.stopPrank();
        uniswapV2Router.addLiquidityETH{value: ETH_DEPOSIT}(
            address(UNREAL_USTB),
            TOKEN_DEPOSIT,
            TOKEN_DEPOSIT,
            ETH_DEPOSIT,
            address(this),
            block.timestamp + 300
        );
    }


    // -------
    // Utility
    // -------

    /**
     * @notice This method allows address(this) to receive ETH.
     */
    receive() external payable {}

    /// @dev Returns the amount of $RWA tokens quoted for `amount` ETH.
    function _getQuoteBuy(uint256 amount) internal returns (uint256) {
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(rwaToken),
            amountIn: amount,
            fee: 100,
            sqrtPriceLimitX96: 0
        });

        (uint256 amountOut,,,) = quoter_2.quoteExactInputSingle(params);
        return amountOut;
    }

    /// @dev Perform a buy
    function _buy(address actor, uint256 amount) internal {
        vm.prank(actor);
        WETH.call{value:amount}(abi.encodeWithSignature("deposit()"));

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(rwaToken),
            fee: 100,
            recipient: actor,
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.startPrank(actor);
        IERC20(WETH).approve(address(router_2), amount);
        router_2.exactInputSingle(swapParams);
        vm.stopPrank();
    }

    /// @dev Returns the amount of ETH quoted for `amount` $RWA.
    function _getQuoteSell(uint256 amount) internal returns (uint256) {
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: address(rwaToken),
            tokenOut: WETH,
            amountIn: amount,
            fee: 100,
            sqrtPriceLimitX96: 0
        });

        (uint256 amountOut,,,) = quoter_2.quoteExactInputSingle(params);
        return amountOut;
    }

    /// @dev Perform a sell
    function _sell(address actor, uint256 amount) internal {
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(rwaToken),
            tokenOut: WETH,
            fee: 100,
            recipient: address(router_2),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data1 = 
            abi.encodeWithSignature(
                "exactInputSingleFeeOnTransfer((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                swapParams.tokenIn,
                swapParams.tokenOut,
                swapParams.fee,
                swapParams.recipient,
                swapParams.deadline,
                swapParams.amountIn,
                swapParams.amountOutMinimum,
                swapParams.sqrtPriceLimitX96
            );

        bytes memory data2 =
            abi.encodeWithSignature(
                "unwrapWETH9(uint256,address)",
                0, // minimum out
                actor
            );
        
        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = data1;
        multicallData[1] = data2;

        vm.startPrank(actor);
        rwaToken.approve(address(router_2), amount);
        address(router_2).call(abi.encodeWithSignature("multicall(bytes[])", multicallData));
        vm.stopPrank();
    }

    /// @dev Helper method for calculate early-burn fees.
    function _calculateFee(uint256 duration) internal view returns (uint16 fee) {
        fee = uint16((veRWA.getMaxEarlyUnlockFee() * duration) / veRWA.MAX_VESTING_DURATION());
    }

    /// @dev Helper method for calculate early-burn penalties post fee.
    function _calculatePenalty(uint256 amount, uint256 duration) internal view returns (uint256 penalty) {
        penalty = (amount * _calculateFee(duration) / 100_00);
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_mainDeployment_init_state() public {

    }


    // ----------
    // Unit Tests
    // ----------

    // RWA buy, sell, transfer ✅
    // veRWA mint, burn, split, merge, migrate, burn, claim ✅
    // delegation
    // rev streams

    // ~ RWAToken Tests ~

    /// @dev Verifies proper state changes when a user buys $RWA tokens from a UniV2Pool.
    function test_mainDeployment_rwaToken_buy() public {

        // ~ Config ~

        uint256 amountETH = 1 ether;
        vm.deal(JOE, amountETH);

        // get quote for buy
        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.fee() / 100;
        assertGt(taxedAmount, 0);

        // ~ Pre-state check ~

        assertEq(JOE.balance, amountETH);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 0);

        // ~ Execute buy ~

        _buy(JOE, amountETH);

        // ~ Post-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), quote - taxedAmount);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), taxedAmount);
    }

    /// @dev Verifies proper state changes when a WHITELISTED user buys $RWA tokens from a UniV2Pool.
    ///      A tax will not be taken from user during buy.
    function test_mainDeployment_rwaToken_buy_WL() public {

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

    /// @dev Verifies proper state changes when a user sells $RWA tokens into a UniV2Pool.
    function test_mainDeployment_rwaToken_sell_single() public {

        // ~ Config ~

        uint256 amountTokens = 5 ether;
        rwaToken.mintFor(JOE, amountTokens);

        // get quote for buy
        uint256 quote = _getQuoteSell(amountTokens);
        uint256 taxedAmount = amountTokens * rwaToken.fee() / 100;
        assertGt(taxedAmount, 0);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 0);

        // ~ Execute sell ~

        _sell(JOE, amountTokens);

        // ~ Post-state check

        assertGt(JOE.balance, 0);
        assertLt(JOE.balance, quote);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), taxedAmount);
    }

    /// @dev Verifies proper state changes when a WHITELISTED user sells $RWA tokens into a UniV2Pool.
    ///      A tax will not be taken from whitelisted user during sell.
    function test_mainDeployment_rwaToken_sell_WL() public {

        // ~ Config ~

        vm.prank(ADMIN);
        rwaToken.excludeFromFees(JOE, true);

        uint256 amountTokens = 5 ether;
        rwaToken.mintFor(JOE, amountTokens);

        // get quote for buy
        uint256 quote = _getQuoteSell(amountTokens);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 0);

        // ~ Execute sell ~

        _sell(JOE, amountTokens);

        // ~ Post-state check

        assertEq(JOE.balance, quote); // no tax taken.
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 0);
    }

    /// @dev Verifies proper state changes when a user transfer tokens to another user.
    ///      Normal pier to pier transfers will result in 0 tax.
    function test_mainDeployment_rwaToken_transfer() public {

        // ~ Config ~

        uint256 amountTokens = 100 ether;
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
    function test_mainDeployment_rwaToken_transfer_WL() public {

        // ~ Config ~

        vm.prank(ADMIN);
        rwaToken.excludeFromFees(JOE, true);

        uint256 amountTokens = 100 ether;
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
    function test_mainDeployment_rwaToken_transfer_fuzzing(uint256 amountTokens) public {
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

    /// @dev Verifies proper taxation and distribution after fees have been modified.
    function test_mainDeployment_rwaToken_royaltyHandler_distributeRoyalties() public {

        // ~ Config ~

        uint256 amountETH = 10 ether;
        vm.deal(JOE, amountETH);

        uint256 quote = _getQuoteBuy(amountETH);
        uint256 taxedAmount = quote * rwaToken.fee() / 100;
        assertGt(taxedAmount, 0);

        uint256 burnPortion = (taxedAmount * royaltyHandler.burnPortion()) / rwaToken.fee(); // 2/5
        uint256 revSharePortion = (taxedAmount * royaltyHandler.revSharePortion()) / rwaToken.fee(); // 2/5

        uint256 preSupply = rwaToken.totalSupply();

        // Execute buy to accumulate fees
        _buy(JOE, amountETH);

        // ~ Pre-state check ~
    
        assertEq(rwaToken.balanceOf(JOE), quote - taxedAmount);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), taxedAmount);
        
        assertEq(rwaToken.totalSupply(), preSupply);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        (uint256 preReserve0, uint256 preReserve1,) = IUniswapV2Pair(pair).getReserves();
        emit log_named_uint("RWA PRE TRANSFER Reserves", preReserve0);
        emit log_named_uint("ETH PRE TRANSFER Reserves", preReserve1);

        // ~ Execute transfer -> distribute ~

        vm.prank(JOE);
        royaltyHandler.distributeRoyalties();

        // ~ Post-state check ~
    
        assertEq(rwaToken.totalSupply(), preSupply - burnPortion);
        assertEq(rwaToken.balanceOf(address(revDistributor)), revSharePortion);

        (uint256 postReserve0, uint256 postReserve1,) = IUniswapV2Pair(pair).getReserves();
        emit log_named_uint("RWA POST TRANSFER Reserves", postReserve0);
        emit log_named_uint("ETH POST TRANSFER Reserves", postReserve1);

        assertGt(postReserve0, preReserve0);
    }


    // ~ VotingEscrowRWA Tests ~

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::mint() is called.
     * @dev State changes:
     *    - contract takes locked tokens ✅
     *    - creates a new lock instance ✅
     *    - user is minted an NFT representing position ✅
     */
    function test_mainDeployment_votingEscrow_mint() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        uint256 totalDuration = (1 * 30 days); // lock for one month

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(tokenId, veRWA.getTokenId() + 1);
        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(amount),
            totalDuration
        );

        // ~ Post-state check ~

        uint256 votingPower = amount.calculateVotingPower(totalDuration);
        emit log_named_uint("1mo MAX Voting Power", votingPower);

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, votingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, votingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), totalDuration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), votingPower);
        assertEq(veRWA.getVotes(JOE), votingPower);

        uint256[] memory joeTokens = api.getNFTsOfOwner(JOE);
        assertEq(joeTokens.length, 1);
        assertEq(joeTokens[0], tokenId);

        uint256[] memory allTokens = api.getAllNFTs();
        assertEq(allTokens.length, 1);
        assertEq(allTokens[0], tokenId);
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::mint() is called with max duration.
     * @dev State changes:
     *    - voting power is 1-to-1 with amount tokens locked ✅
     */
    function test_mainDeployment_votingEscrow_mint_max() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(tokenId, veRWA.getTokenId() + 1);
        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            36 * 30 days // max lock time
        );

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
    }

    /**
     * @notice This unit test verifies proper state changes when there are consecutive mints.
     * @dev State Changes:
     *    - getTotalVotingPowerCheckpoints will contain 1 large checkpoint ✅
     */
    function test_mainDeployment_votingEscrow_mint_multiple() public {

        // ~ Config ~

        uint256 amount1 = 600 ether;        
        uint256 amount2 = 400 ether;
        rwaToken.mintFor(JOE, amount1 + amount2);

        uint256 tokenId = veRWA.getTokenId();

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amount1 + amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 1 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount1);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount1);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1);
        assertEq(veRWA.getVotes(JOE), amount1);

        // ~ Joe executes mint (again) ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount2);
        veRWA.mint(
            JOE,
            uint208(amount2),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 2 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount2);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1 + amount2); // 1_000

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1 + amount2); // 1_000
        assertEq(veRWA.getVotes(JOE), amount1 + amount2);

        uint256[] memory joeTokens = api.getNFTsOfOwner(JOE);
        assertEq(joeTokens.length, 2);
        assertEq(joeTokens[0], tokenId-1);
        assertEq(joeTokens[1], tokenId);

        uint256[] memory allTokens = api.getAllNFTs();
        assertEq(allTokens.length, 2);
        assertEq(allTokens[0], tokenId-1);
        assertEq(allTokens[1], tokenId);
    }

    /**
     * @notice This unit test verifies proper state changes when there are consecutive mints after
     *         time has past. This should create another element in `_totalVotingPowerCheckpoints`.
     * @dev State Changes:
     *    - getTotalVotingPowerCheckpoints will contain 2 checkpoints instead of 1 ✅
     */
    function test_mainDeployment_votingEscrow_mint_multiple_skip() public {

        // ~ Config ~

        uint256 amount1 = 600 ether;
        uint256 amount2 = 400 ether;
        rwaToken.mintFor(JOE, amount1 + amount2);

        uint256 tokenId = veRWA.getTokenId();

        uint256 timestamp = block.timestamp;

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amount1 + amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 1 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount1);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount1);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1);
        assertEq(veRWA.getVotes(JOE), amount1);

        // ~ Joe executes mint (again) ~

        skip(10);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount2);
        veRWA.mint(
            JOE,
            uint208(amount2),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 2 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount2);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, timestamp + 10);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1); // 600
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, timestamp + 10);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, amount1 + amount2); // 1_000

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1 + amount2); // 1_000
        assertEq(veRWA.getVotes(JOE), amount1 + amount2);
    }


    // ~ VotingEscrowVesting ~

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::deposit() is called.
     * @dev State changes:
     *    - contract takes VE NFT ✅
     *    - VE lock instance (on veRWA) is updated ✅
     *    - vesting contract is updated appropriately ✅
     */
    function test_mainDeployment_votingEscrow_deposit() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            36 * 30 days // max lock time
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 start;
        uint256 end;
        uint256 amount;

        uint256[] memory depositedTokens;

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amountTokens);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amountTokens);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amountTokens);
        assertEq(veRWA.getVotes(JOE), amountTokens);

        // check vesting schedule data
        (start, end, amount) = vesting.vestingSchedules(tokenId);
        assertEq(start, 0);
        assertEq(end, 0);
        assertEq(amount, 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));

        // ~ Joe executes deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check vesting schedule data
        (start, end, amount) = vesting.vestingSchedules(tokenId);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + (36 * 30 days));
        assertEq(amount, amountTokens);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        assertEq(vesting.depositedTokensIndex(tokenId), 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);
    }

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::withdraw() is called.
     * @dev State changes:
     *    - contract sends user VE NFT ✅
     *    - calculates a remainting time and updates veRWA ✅
     *    - vesting contract is updated appropriately ✅
     */
    function test_mainDeployment_votingEscrow_withdraw() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        uint256 totalDuration = (2 * 30 days);
        uint256 skipTo = (1 * 30 days);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            totalDuration // 2 month lock time
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 startTime;
        uint256 endTime;
        uint256 amount;

        uint256[] memory depositedTokens;

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check vesting schedule data
        (startTime, endTime, amount) = vesting.vestingSchedules(tokenId);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + totalDuration);
        assertEq(amount, amountTokens);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        assertEq(vesting.depositedTokensIndex(tokenId), 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip ~

        skip(skipTo);

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // check vesting schedule data
        (startTime, endTime, amount) = vesting.vestingSchedules(tokenId);
        assertEq(startTime, block.timestamp - skipTo);
        assertEq(endTime, block.timestamp + skipTo);
        assertEq(amount, amountTokens);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        assertEq(vesting.depositedTokensIndex(tokenId), 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ withdraw ~

        vm.prank(JOE);
        vesting.withdraw(JOE, tokenId);

        uint256 votingPower = amount.calculateVotingPower(totalDuration - skipTo);
        emit log_named_uint("MAX VOTING POWER", amount.calculateVotingPower(totalDuration));
        emit log_named_uint("WITHDRAW VOTING POWER", votingPower);

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, votingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, votingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), totalDuration - skipTo);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), votingPower);
        assertEq(veRWA.getVotes(JOE), votingPower);

        // check vesting schedule data
        (startTime, endTime, amount) = vesting.vestingSchedules(tokenId);
        assertEq(startTime, 0);
        assertEq(endTime, 0);
        assertEq(amount, 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::burn() is called.
     * @dev State changes:
     *    - a token that is deposited for the entire promised duration can withdraw and burn ✅
     *    - proper state changes for vesting and veRWA ✅
     *    - NFT no longer exists once burn() is executed ✅
     *    - actor (Joe) receives 100% of locked tokens ✅
     */
    function test_mainDeployment_votingEscrow_withdrawThenBurn() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 duration = 36 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        vm.warp(block.timestamp + 1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to end of vesting ~

        vm.warp(block.timestamp + duration);

        // ~ Withdraw ~

        vm.startPrank(JOE);
        vesting.withdraw(JOE, tokenId);

        // ~ Post-state check 1 ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));

        // ~ Burn ~

        vm.startPrank(JOE);
        veRWA.burn(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check 2 ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::burn() is called before
     *         the end of the lock period is reached.
     * @dev State changes:
     *    - actor (Joe) receives 50% of locked tokens ✅
     *    - penalized tokens are burned ✅
     *    - early unlock == fee ✅
     */
    function test_mainDeployment_votingEscrow_burn_early() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 duration = 36 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        uint256 preSupply = rwaToken.totalSupply();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Burn ~

        vm.startPrank(JOE);
        veRWA.burn(JOE, tokenId);
        vm.stopPrank();

        uint256 feeTaken = _calculatePenalty(amount, duration);

        // ~ Post-state check 2 ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), (amount / 2));
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertNotEq(preSupply, rwaToken.totalSupply());
        assertEq(feeTaken + rwaToken.balanceOf(JOE), amount);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::burn() is called before
     *         the end of the lock period is reached.
     * @dev State changes:
     *    - actor (Joe) receives 75% of locked tokens ✅
     *    - penalized tokens are burned ✅
     *    - early unlock == fee ✅
     */
    function test_mainDeployment_votingEscrow_withdrawThenBurn_early() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 duration = 36 * 30 days;
        uint256 skipTo = duration / 2;

        uint256 penalty = _calculatePenalty(amount, skipTo);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to middle of vesting ~

        skip(skipTo);

        // ~ Withdraw ~

        vm.startPrank(JOE);
        vesting.withdraw(JOE, tokenId);

        // ~ Post-state check 1 ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[2]._value, maxVotingPower/2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 3);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._value, maxVotingPower/2);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration - skipTo);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower/2);
        assertEq(veRWA.getVotes(JOE), maxVotingPower/2);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));

        // ~ Burn ~

        vm.startPrank(JOE);
        veRWA.burn(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check 2 ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount - penalty);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[2]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 3);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::claim() is called.
     * @dev State changes:
     *    - a token that is deposited for the entire promised duration can claim ✅
     *    - proper state changes for vesting and veRWA ✅
     *    - NFT no longer exists once claim() is executed ✅
     */
    function test_mainDeployment_votingEscrow_claim() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 duration = 36 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        vm.warp(block.timestamp + 1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to end of vesting ~

        vm.warp(block.timestamp + duration);

        // ~ Claim ~

        vm.prank(JOE);
        vesting.claim(JOE, tokenId);

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::claim() is called before
     *         the end of the lock period is reached.
     * @dev State changes:
     *    - a fee is applied ✅
     */
    function test_mainDeployment_votingEscrow_claim_early() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 duration = 36 * 30 days;
        uint256 penalty = _calculatePenalty(amount, duration);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ claim ~

        vm.startPrank(JOE);
        vesting.claim(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount - penalty);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::merge() is called.
     * @dev State changes:
     *    - token1 lock data is set to 0 then burned ✅
     *    - token2 lock duration is set to greater duration between 2 tokens ✅
     *    - token2 locked tokens are combined with token1's locked tokens ✅
     */
    function test_mainDeployment_votingEscrow_merge() public {

        // ~ Config ~

        uint256 amount1 = 1_000 ether;
        uint256 amount2 = 1_000 ether;

        rwaToken.mintFor(JOE, amount1);
        rwaToken.mintFor(ALICE, amount2);

        uint256 duration1 = 1 * 30 days;
        uint256 duration2 = 2 * 30 days;

        // Mint Joe VE NFT
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        uint256 tokenId1 = veRWA.mint(
            JOE,
            uint208(amount1),
            duration1
        );
        vm.stopPrank();

        // Mint Alice VE NFT
        vm.startPrank(ALICE);
        rwaToken.approve(address(veRWA), amount2);
        uint256 tokenId2 = veRWA.mint(
            ALICE,
            uint208(amount2),
            duration2
        );
        vm.stopPrank();

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 maxVotingPower1 = amount1.calculateVotingPower(duration1);
        uint256 maxVotingPower2 = amount2.calculateVotingPower(duration2);

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId1), JOE);
        assertEq(veRWA.ownerOf(tokenId2), ALICE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId1), amount1);
        assertEq(veRWA.getLockedAmount(tokenId2), amount2);
        // get voting power checkpoints for tokenId1
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId1);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1);
        // get voting power checkpoints for tokenId2
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId2);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1 + maxVotingPower2);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId1), duration1);
        assertEq(veRWA.getRemainingVestingDuration(tokenId2), duration2);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower1);
        assertEq(veRWA.getVotes(JOE), maxVotingPower1);
        assertEq(veRWA.getAccountVotingPower(ALICE), maxVotingPower2);
        assertEq(veRWA.getVotes(ALICE), maxVotingPower2);

        // ~ Skip to create checkpoint ~

        skip(1);

        // ~ Merge ~

        // Joe sends NFT to Alice
        vm.prank(JOE);
        veRWA.transferFrom(JOE, ALICE, tokenId1);

        // Verify Alice holds total voting power (even with tokens not merged yet)
        assertEq(veRWA.ownerOf(tokenId1), ALICE);
        assertEq(veRWA.ownerOf(tokenId2), ALICE);
        assertEq(veRWA.getAccountVotingPower(ALICE), maxVotingPower1 + maxVotingPower2);
        assertEq(veRWA.getVotes(ALICE), maxVotingPower1 + maxVotingPower2);

        // Alice merges both tokens
        vm.prank(ALICE);
        veRWA.merge(tokenId1, tokenId2);

        uint256 combinedVotingPower = (amount1 + amount2).calculateVotingPower(duration2);

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId1); // token n longer exists

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId1), 0);
        assertEq(veRWA.getLockedAmount(tokenId2), amount1 + amount2);
        // get voting power checkpoints for tokenId1
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId1);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        // get voting power checkpoints for tokenId2
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId2);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower2);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, combinedVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1 + maxVotingPower2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, combinedVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId2), duration2);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);
        assertEq(veRWA.getAccountVotingPower(ALICE), combinedVotingPower);
        assertEq(veRWA.getVotes(ALICE), combinedVotingPower);
    }

    // ~ RWAVotingEscrow::split ~

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::split() is called.
     * @dev State changes:
     *    - token locked balance is split according to specified proportion ✅
     *    - locked duration stays the same for all tokens ✅
     */
    function test_mainDeployment_votingEscrow_split() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        rwaToken.mintFor(JOE, amountTokens);

        uint256 duration = 1 * 30 days;

        // should yield 2 equal tokens
        uint256[] memory shares = new uint256[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(amountTokens),
            duration
        );
        vm.stopPrank();

        uint256 maxVotingPower = amountTokens.calculateVotingPower(duration);
        uint256 maxVotingPowerSplit = (amountTokens/2).calculateVotingPower(duration);

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower);
        assertEq(veRWA.getVotes(JOE), maxVotingPower);

        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Split ~

        vm.prank(JOE);
        uint256[] memory tokenIds = veRWA.split(tokenId, shares);

        // ~ Post-state check ~

        assertEq(tokenIds[0], tokenId);
        assertEq(tokenIds.length, shares.length);
        
        assertEq(veRWA.getLockedAmount(tokenIds[0]), amountTokens/2);
        assertEq(veRWA.getLockedAmount(tokenIds[1]), amountTokens/2);
        // get voting power checkpoints for tokenId1
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenIds[0]);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, maxVotingPowerSplit);
        // get voting power checkpoints for tokenId2
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenIds[1]);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPowerSplit);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, maxVotingPower - 1);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenIds[0]), duration);
        assertEq(veRWA.getRemainingVestingDuration(tokenIds[1]), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower - 1);
        assertEq(veRWA.getVotes(JOE), maxVotingPower - 1);
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::migrate() is called.
     * @dev State changes:
     *    - Method can only be called by layer zero endpoint ✅
     *    - $RWA tokens are minted to VE contract 1-to-1 with lockedBalance ✅
     *    - Receiver is minted a VE NFT representing specified position ✅
     */
    function test_mainDeployment_votingEscrow_migrate() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 duration = 1 * 30 days;

        uint256 preSupply = rwaToken.totalSupply();
        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(NIK), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check NIK's voting power
        assertEq(veRWA.getAccountVotingPower(NIK), 0);
        assertEq(veRWA.getVotes(NIK), 0);

        // ~ Migrate ~

        // Joe tries calling migrate -> revert
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAVotingEscrow.NotAuthorized.selector, JOE));
        veRWA.migrate(NIK, amount, duration);

        vm.prank(UNREAL_ENDPOINT);
        uint256 _tokenId = veRWA.migrate(NIK, amount, duration);

        // ~ Post-state check ~

        assertEq(tokenId, _tokenId);
        assertEq(rwaToken.totalSupply(), preSupply + amount);

        assertEq(rwaToken.balanceOf(NIK), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);

        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check NIK's voting power
        assertEq(veRWA.getAccountVotingPower(NIK), maxVotingPower);
        assertEq(veRWA.getVotes(NIK), maxVotingPower);
    }

    /**
     * @notice This unit test verifies proper values when RWAVotingEscrow::getPastVotingPower() is called.
     * @dev State changes:
     *    - getPastVotingPower always pulls the most recent updated key-value pair for a token ✅
     */
    function test_mainDeployment_votingEscrow_getPastVotingPower() public {
        // mint token, deposit, skip, withdraw, deposit, skip, withdraw
        // to create checkpoints, checking state each time a withdraw happens

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        rwaToken.mintFor(JOE, amountTokens);
        
        uint256 duration = 4 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(amountTokens),
            duration
        );
        vm.stopPrank();

        uint256 maxVotingPower = amountTokens.calculateVotingPower(duration);

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Skip ~

        skip(1);

        // ~ Voting power check 1 ~

        // verify voting power via upperLookup
        assertEq(veRWA.getPastVotingPower(tokenId, block.timestamp - 1), maxVotingPower);
        assertEq(veRWA.getPastTotalVotingPower(block.timestamp - 1), maxVotingPower);

        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower);
        assertEq(veRWA.getVotes(JOE), maxVotingPower);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Skip ~

        skip(1);

        // ~ Voting power check 2 ~

        // verify voting power via upperLookup
        assertEq(veRWA.getPastVotingPower(tokenId, block.timestamp - 1), 0);
        assertEq(veRWA.getPastTotalVotingPower(block.timestamp - 1), 0);

        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // ~ Withdraw ~ 

        vm.startPrank(JOE);
        vesting.withdraw(JOE, tokenId);

        uint256 vpAfter1 = amountTokens.calculateVotingPower(duration - 1);

        // ~ Skip ~

        skip(1);

        // ~ Voting power check 3 ~

        assertLt(vpAfter1, maxVotingPower);

        // verify voting power via upperLookup
        assertEq(veRWA.getPastVotingPower(tokenId, block.timestamp - 1), vpAfter1);
        assertEq(veRWA.getPastTotalVotingPower(block.timestamp - 1), vpAfter1);

        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - 2);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[2]._value, vpAfter1);
        
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), vpAfter1);
        assertEq(veRWA.getVotes(JOE), vpAfter1);
    }


    // ~ Delegation ~

    /// @dev Verifies state when RWAVotingEscrow::delegate is executed.
    function test_mainDeployment_delegation_delegate() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(ADMIN, amount);

        uint256 totalDuration = (36 * 30 days); // lock for max
        Checkpoints.Trace208 memory delegateCheckpoints;

        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            totalDuration
        );
        vm.stopPrank();

        // ~ Pre-state check ~

        uint256 votingPower = amount.calculateVotingPower(totalDuration);
        emit log_named_uint("max duration MAX Voting Power", votingPower);

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 0);

        // ~ Admin delegates to Joe ~

        skip(1);

        vm.prank(ADMIN);
        veRWA.delegate(JOE);

        // ~ Post-state check 1 ~

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(JOE), votingPower);

        assertEq(veRWA.delegates(ADMIN), JOE);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 2);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);

        // ~ Admin delegates to himself ~

        skip(1);

        vm.prank(ADMIN);
        veRWA.delegate(ADMIN);

        // ~ Post-state check 2 ~

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 3);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 2);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);
        assertEq(delegateCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[2]._value, votingPower);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 2);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);
    }

    /// @dev Verifies state when DelegateFactory::deployDelegator is executed.
    function test_mainDeployment_delegation_deployDelegator() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(ADMIN, amount);

        uint256 totalDuration = (36 * 30 days); // lock for max
        Checkpoints.Trace208 memory delegateCheckpoints;

        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            totalDuration
        );

        // ~ Pre-state check ~

        uint256 votingPower = amount.calculateVotingPower(totalDuration);
        emit log_named_uint("max duration MAX Voting Power", votingPower);

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 0);

        // ~ Execute deployDelegator ~

        skip(1);

        // Admin delegates voting power to Joe for 1 month.
        vm.startPrank(ADMIN);
        veRWA.approve(address(delegateFactory), tokenId);
        address delegator = delegateFactory.deployDelegator(
            tokenId,
            JOE,
            (30 days)
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(delegator));
        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertEq(veRWA.getAccountVotingPower(address(delegator)), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), votingPower);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), JOE);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 2);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(address(delegator));
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, 0);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
    }

    /// @dev Verifies state when DelegateFactory::revokeExpiredDelegators is called
    function test_mainDeployment_delegation_revokeAndDelete() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(ADMIN, amount);

        uint256 totalDuration = (36 * 30 days); // lock for max

        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            totalDuration
        );

        uint256 votingPower = amount.calculateVotingPower(totalDuration);

        // Admin delegates voting power to Joe for 1 month.
        vm.startPrank(ADMIN);
        veRWA.approve(address(delegateFactory), tokenId);
        address delegator = delegateFactory.deployDelegator(
            tokenId,
            JOE,
            (30 days)
        );
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(delegateFactory.getDelegatorsArray().length, 1);
        assertEq(delegateFactory.delegatorExpiration(delegator), block.timestamp + (30 days));
        assertEq(delegateFactory.isDelegator(delegator), true);
        assertEq(delegateFactory.expiredDelegatorExists(), false);
        assertEq(delegateFactory.isExpiredDelegator(delegator), false);

        assertEq(veRWA.ownerOf(tokenId), address(delegator));
        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertEq(veRWA.getAccountVotingPower(address(delegator)), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), votingPower);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), JOE);

        // ~ Skip to expiration and check ~

        skip(30 days);

        assertEq(delegateFactory.expiredDelegatorExists(), true);
        assertEq(delegateFactory.isExpiredDelegator(delegator), true);

        // ~ Execute revokeExpiredDelegators ~

        delegateFactory.revokeExpiredDelegators();

        // ~ Post-state check ~

        assertEq(delegateFactory.getDelegatorsArray().length, 0);
        assertEq(delegateFactory.delegatorExpiration(delegator), 0);
        assertEq(delegateFactory.isDelegator(delegator), false);
        assertEq(delegateFactory.expiredDelegatorExists(), false);

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(address(delegator)), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), address(delegator));

        // restrictions test -> random address will return false
        assertEq(delegateFactory.isExpiredDelegator(address(1)), false);
    }

    /// @dev Verifies state when DelegateFactory::revokeExpiredDelegators is called to revoke multiple delegators
    function test_mainDeployment_delegation_revokeAndDelete_multiple() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(ADMIN, amount);

        uint256 numDelegators = 4;
        uint256 totalDuration = (36 * 30 days); // lock for max

        uint256[] memory tokenIds = new uint256[](numDelegators);
        address[] memory delegators = new address[](numDelegators);

        // Mint Admin $RWA tokens
        rwaToken.mintFor(ADMIN, amount * numDelegators);

        for (uint256 i; i < numDelegators; ++i) {
            vm.startPrank(ADMIN);
            rwaToken.approve(address(veRWA), amount);
            tokenIds[i] = veRWA.mint(
                ADMIN,
                uint208(amount),
                totalDuration
            );
            vm.stopPrank();
        }

        uint256 votingPower = amount.calculateVotingPower(totalDuration);

        // Admin delegates voting power to Joe for 1 month.
        for (uint256 i; i < numDelegators; ++i) {
            vm.startPrank(ADMIN);
            veRWA.approve(address(delegateFactory), tokenIds[i]);
            delegators[i] = delegateFactory.deployDelegator(
                tokenIds[i],
                JOE,
                (30 days)
            );
            vm.stopPrank();
        }

        // ~ Pre-state check ~

        assertEq(delegateFactory.getDelegatorsArray().length, numDelegators);
        
        for (uint256 i; i < numDelegators; ++i) {
            assertEq(delegateFactory.delegatorExpiration(delegators[i]), block.timestamp + (30 days));
            assertEq(delegateFactory.isDelegator(delegators[i]), true);
            assertEq(delegateFactory.expiredDelegatorExists(), false);
            assertEq(delegateFactory.isExpiredDelegator(delegators[i]), false);

            assertEq(veRWA.ownerOf(tokenIds[i]), delegators[i]);
            assertEq(veRWA.getAccountVotingPower(delegators[i]), votingPower);
            assertEq(veRWA.getVotes(delegators[i]), 0);
            assertEq(veRWA.delegates(delegators[i]), JOE);
        }

        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(JOE), votingPower * numDelegators);

        // ~ Skip to expiration and check ~

        skip(30 days);

        assertEq(delegateFactory.expiredDelegatorExists(), true);
        for (uint256 i; i < numDelegators; ++i) {
            assertEq(delegateFactory.isExpiredDelegator(delegators[i]), true);
        }

        // ~ Execute revokeExpiredDelegators ~

        delegateFactory.revokeExpiredDelegators();

        // ~ Post-state check ~

        assertEq(veRWA.getVotes(ADMIN), votingPower * numDelegators);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        assertEq(delegateFactory.getDelegatorsArray().length, 0);
        
        for (uint256 i; i < numDelegators; ++i) {
            assertEq(delegateFactory.delegatorExpiration(delegators[i]), 0);
            assertEq(delegateFactory.isDelegator(delegators[i]), false);
            assertEq(delegateFactory.expiredDelegatorExists(), false);

            assertEq(veRWA.ownerOf(tokenIds[i]), ADMIN);
            assertEq(veRWA.getAccountVotingPower(delegators[i]), 0);
            assertEq(veRWA.getVotes(delegators[i]), 0);
            assertEq(veRWA.delegates(delegators[i]), delegators[i]);
        }

        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower * numDelegators);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower * numDelegators);
        assertEq(veRWA.getVotes(JOE), 0);
    }


    // ~ Revenue Distributor ~

    /// @dev This unit test verifies proper state changes when RevenueDistributor::convertRewardToken is executed.
    function test_mainDeployment_revDist_convertRewardToken_single_UniV3() public {

        // ~ Config ~

        uint256 amountIn = 50 ether;
        deal(address(UNREAL_DAI), address(revDistributor), amountIn);

        //uint256 quoteOut = _getQuoteSell(amountIn);
        uint256 preBal = address(revStreamETH).balance;

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(UNREAL_DAI),
            tokenOut: WETH,
            fee: 1000,
            recipient: address(UNREAL_SWAP_ROUTER),
            deadline: block.timestamp + 100,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data1 = 
            abi.encodeWithSignature(
                "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                swapParams.tokenIn,
                swapParams.tokenOut,
                swapParams.fee,
                swapParams.recipient,
                swapParams.deadline,
                swapParams.amountIn,
                swapParams.amountOutMinimum,
                swapParams.sqrtPriceLimitX96
            );

        bytes memory data2 =
            abi.encodeWithSignature(
                "unwrapWETH9(uint256,address)",
                0, // minimum out
                address(revDistributor)
            );
        
        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = data1;
        multicallData[1] = data2;

        // ~ Pre-state check ~

        assertEq(IERC20(UNREAL_DAI).balanceOf(address(revDistributor)), amountIn);
        assertEq(address(revStreamETH).balance, preBal);

        // ~ Execute RevenueDistributor::convertRewardToken ~

        vm.startPrank(ADMIN);
        revDistributor.convertRewardToken(
            address(UNREAL_DAI),
            amountIn,
            UNREAL_SWAP_ROUTER,
            abi.encodeWithSignature("multicall(bytes[])", multicallData)
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(IERC20(UNREAL_DAI).balanceOf(address(revDistributor)), 0);
        assertGt(address(revStreamETH).balance, preBal);
    }

    /// @dev This unit test verifies proper state changes when RevenueDistributor::convertRewardTokenBatch is executed.
    function test_mainDeployment_revDist_convertRewardTokenBatch_claimable() public {

        // ~ Config ~

        uint256 amountIn = 5 ether;

        rwaToken.mintFor(JOE, amountIn);
        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountIn);
        veRWA.mint(
            JOE,
            uint208(amountIn),
            (1 * 30 days)
        );
        vm.stopPrank();

        rwaToken.mintFor(address(revDistributor), amountIn);
        //deal(address(UNREAL_USTB), address(revDistributor), amountIn);
        vm.prank(0x95e3664633A8650CaCD2c80A0F04fb56F65DF300); // USTB holder
        IERC20(address(UNREAL_USTB)).transfer(address(revDistributor), amountIn);
        deal(address(UNREAL_DAI), address(revDistributor), amountIn);

        // DAI -> WETH using UniV3

        ISwapRouter.ExactInputSingleParams memory swapParamsDAI = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(UNREAL_DAI),
            tokenOut: WETH,
            fee: 1000,
            recipient: address(UNREAL_SWAP_ROUTER),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data1 = 
            abi.encodeWithSignature(
                "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                swapParamsDAI.tokenIn,
                swapParamsDAI.tokenOut,
                swapParamsDAI.fee,
                swapParamsDAI.recipient,
                swapParamsDAI.deadline,
                swapParamsDAI.amountIn,
                swapParamsDAI.amountOutMinimum,
                swapParamsDAI.sqrtPriceLimitX96
            );

        bytes memory data2 =
            abi.encodeWithSignature(
                "unwrapWETH9(uint256,address)",
                0, // minimum out
                address(revDistributor)
            );
        
        bytes[] memory multicallDataDAI = new bytes[](2);
        multicallDataDAI[0] = data1;
        multicallDataDAI[1] = data2;

        // RWA -> WETH using UniV3

        ISwapRouter.ExactInputSingleParams memory swapParamsRWA = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(rwaToken),
            tokenOut: WETH,
            fee: 100,
            recipient: address(router_2),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        data1 = abi.encodeWithSignature(
                "exactInputSingleFeeOnTransfer((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                swapParamsRWA.tokenIn,
                swapParamsRWA.tokenOut,
                swapParamsRWA.fee,
                swapParamsRWA.recipient,
                swapParamsRWA.deadline,
                swapParamsRWA.amountIn,
                swapParamsRWA.amountOutMinimum,
                swapParamsRWA.sqrtPriceLimitX96
            );

        data2 = abi.encodeWithSignature(
                "unwrapWETH9(uint256,address)",
                0, // minimum out
                address(revDistributor)
            );
        
        bytes[] memory multicallDataRWA = new bytes[](2);
        multicallDataRWA[0] = data1;
        multicallDataRWA[1] = data2;

        // USTB -> WETH using UniV2 & config

        address[] memory pathUSTB = new address[](2);
        pathUSTB[0] = address(UNREAL_USTB);
        pathUSTB[1] = WETH;

        address[] memory tokens = new address[](3);
        tokens[0] = address(rwaToken);
        tokens[1] = address(UNREAL_USTB);
        tokens[2] = address(UNREAL_DAI);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
        amounts[2] = amountIn;

        address[] memory targets = new address[](3);
        targets[0] = address(router_2);
        targets[1] = UNREAL_UNIV2_ROUTER;
        targets[2] = UNREAL_SWAP_ROUTER;

        bytes[] memory data = new bytes[](3);
        data[0] = 
            abi.encodeWithSignature("multicall(bytes[])", multicallDataRWA);
        data[1] = 
            abi.encodeWithSignature(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                amountIn,
                0,
                pathUSTB,
                address(revDistributor),
                block.timestamp + 100
            );
        data[2] = 
            abi.encodeWithSignature("multicall(bytes[])", multicallDataDAI);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(address(revDistributor)), amountIn);
        assertEq(IERC20(address(UNREAL_USTB)).balanceOf(address(revDistributor)), amountIn);
        assertEq(IERC20(address(UNREAL_DAI)).balanceOf(address(revDistributor)), amountIn);
        assertEq(address(revStreamETH).balance, 0);

        // ~ Execute RevenueDistributor::convertRewardToken ~

        vm.startPrank(ADMIN);
        revDistributor.convertRewardTokenBatch(
            tokens,
            amounts,
            targets,
            data
        );
        vm.stopPrank();

        // ~ Post-state check ~

        // assertEq(amountsOut[0], quoteOut1); 0.094803704666332798 ETH from RWA
        // assertEq(amountsOut[1], quoteOut2); 0.049602730389010781 ETH from USTB
        // assertEq(amountsOut[2], quoteOut3); 0.000998992512735895 ETH from DAI

        // 0.145405427568079474 ETH total distributed

        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);
        assertEq(IERC20(address(UNREAL_USTB)).balanceOf(address(revDistributor)), 0);
        assertEq(IERC20(address(UNREAL_DAI)).balanceOf(address(revDistributor)), 0);
        assertGt(address(revStreamETH).balance, 0);

        // ~ Call claimable ~

        skip(1);
        assertEq(revStreamETH.claimable(JOE), address(revStreamETH).balance);
    }


    // ~ Revenue Stream ~

    /// @dev Verifies proper state changes when RevenueStreamETH::depositETH() is executed.
    function test_mainDeployment_revStreamETH_depositETH() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        vm.deal(address(revDistributor), amount);

        // ~ Pre-state check ~

        assertEq(address(revStreamETH).balance, 0);
        assertEq(address(revDistributor).balance, amount);

        uint256[] memory cycles = revStreamETH.getCyclesArray();
        assertEq(cycles.length, 1);
        assertEq(cycles[0], block.timestamp);

        // ~ Execute Deposit ~

        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amount}();

        // ~ Post-state check ~

        assertEq(address(revStreamETH).balance, amount);
        assertEq(address(revDistributor).balance, 0);

        assertEq(revStreamETH.revenue(block.timestamp), amount);

        cycles = revStreamETH.getCyclesArray();
        assertEq(cycles.length, 2);
        assertEq(cycles[0], block.timestamp);
        assertEq(cycles[1], block.timestamp);
    }

    /// @dev Verifies proper return variable when RevenueStreamETH::claimable() is called.
    function test_mainDeployment_revStreamETH_claimable_single() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(amount),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Call claimable ~

        uint256 claimable = revStreamETH.claimable(JOE);

        // ~ Verify ~

        assertEq(claimable, amountRevenue);
        assertEq(api.getClaimable(JOE), claimable);
    }

    /// @dev Verifies proper return variable when RevenueStreamETH::claimable() is called.
    function test_mainDeployment_revStreamETH_claimable_multiple() public {

        // ~ Config ~

        uint256 amount1 = 1_000 ether;
        // Mint Joe more$RWA tokens
        rwaToken.mintFor(JOE, amount1 * 2);

        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue/2}();

        skip(1);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue/2}();
        

        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Call claimable ~

        uint256 claimableJoe = revStreamETH.claimable(JOE);

        // ~ Verify ~

        assertEq(claimableJoe, amountRevenue);
        assertEq(api.getClaimable(JOE), claimableJoe);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::claim() is executed.
    function test_mainDeployment_revStreamETH_claim_single() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(JOE, amount);

        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(amount),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue * 3);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();
        revStreamETH.depositETH{value: amountRevenue}();
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(address(revStreamETH).balance, amountRevenue * 2);
        assertEq(revStreamETH.lastClaim(JOE), 0);

        uint256 claimable = revStreamETH.claimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        // ~ Post-state check 1 ~

        assertEq(claimable, amountRevenue * 2);
        assertEq(JOE.balance, amountRevenue * 2);
        assertEq(address(revStreamETH).balance, 0);
        assertEq(revStreamETH.lastClaim(JOE), block.timestamp - 1);

        // ~ Another deposit ~

        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        claimable = revStreamETH.claimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        // ~ Post-state check 2 ~

        assertEq(claimable, amountRevenue);
        assertEq(JOE.balance, amountRevenue * 3);
        assertEq(address(revStreamETH).balance, 0);
        assertEq(revStreamETH.lastClaim(JOE), block.timestamp - 1);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::claim() is executed.
    function test_mainDeployment_revStreamETH_claim_multiple() public {

        // ~ Config ~

        uint256 amount1 = 1_000 ether;
        // Mint Joe more$RWA tokens
        rwaToken.mintFor(JOE, amount1*2);

        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(address(revStreamETH).balance, amountRevenue);
        assertEq(revStreamETH.lastClaim(JOE), 0);

        assertEq(revStreamETH.claimable(JOE), amountRevenue);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        // ~ Post-state check ~

        assertEq(JOE.balance, amountRevenue);
        assertEq(address(revStreamETH).balance, 0);
        assertEq(revStreamETH.lastClaim(JOE), block.timestamp - 1);

        assertEq(revStreamETH.claimable(JOE), 0);
    }

    /// @dev Verifies delegatees can claim rent. 
    function test_mainDeployment_revStreamETH_claim_delegate() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // Mint ADMIN $RWA tokens
        rwaToken.mintFor(ADMIN, amount);

        // mint ADMIN veRWA token
        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            duration
        );

        // Admin delegates voting power to Joe for 1 month.
        vm.startPrank(ADMIN);
        veRWA.approve(address(delegateFactory), tokenId);
        address delegator = delegateFactory.deployDelegator(
            tokenId,
            JOE,
            (30 days)
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        assertEq(ADMIN.balance, 0);
        assertEq(JOE.balance, 0);
        assertEq(address(revStreamETH).balance, amountRevenue);
        assertEq(revStreamETH.lastClaim(ADMIN), 0);
        assertEq(revStreamETH.lastClaim(JOE), 0);

        assertEq(revStreamETH.claimable(JOE), amountRevenue);

        assertEq(veRWA.ownerOf(tokenId), address(delegator));
        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertGt(veRWA.getAccountVotingPower(address(delegator)), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertGt(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        // ~ Post-state check 1 ~

        assertEq(JOE.balance, amountRevenue);
        assertEq(address(revStreamETH).balance, 0);
        assertEq(revStreamETH.lastClaim(JOE), block.timestamp - 1);
    }

    /// @dev Verifies proper return variable when RevenueStreamETH::expiredRevenue() is called.
    function test_revStreamETH_expiredRevenue_single() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        rwaToken.mintFor(JOE, amount);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue);
        assertEq(revStreamETH.expiredRevenue(), 0);

        // ~ Skip to expiration ~

        skip(revStreamETH.timeUntilExpired());

        // ~ Post-state check ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue);

        // ~ Joe claims ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        // ~ Post-state check 2 ~

        assertEq(revStreamETH.claimable(JOE), 0);
        assertEq(revStreamETH.expiredRevenue(), 0);
    }

    // ~ handling expired revenue ~

    /// @dev Verifies proper return variable when RevenueStreamETH::expiredRevenue() is called.
    function test_mainDeployment_revStreamETH_expiredRevenue_multiple() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        rwaToken.mintFor(JOE, amount);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(revStreamETH.timeUntilExpired()-3);

        // ~ Pre-state check ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue * 3);
        assertEq(revStreamETH.expiredRevenue(), 0);

        // ~ Skip to expiration 1 ~

        skip(1); // first deposit is now expired

        // ~ Post-state check 1 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue * 3);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue);

        // ~ Skip to expiration 2 ~

        skip(1); // second deposit + first is now expired

        // ~ Post-state check 2 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue * 3);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue * 2);

        // ~ Skip to expiration 3 ~

        skip(1); // third deposit + second + first is now expired

        // ~ Post-state check 3 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue * 3);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue * 3);

        // ~ Joe claims ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        // ~ Post-state check 4 ~

        assertEq(revStreamETH.claimable(JOE), 0);
        assertEq(revStreamETH.expiredRevenue(), 0);
    }

    function test_mainDeployment_revStreamETH_skimExpiredRevenue_single() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        rwaToken.mintFor(JOE, amount);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue);
        assertEq(revStreamETH.expiredRevenue(), 0);

        // ~ Attempt to skim -> Revert ~

        vm.prank(ADMIN);
        vm.expectRevert("No expired revenue claimable");
        revStreamETH.skimExpiredRevenue();

        // ~ Skip to expiration ~

        skip(revStreamETH.timeUntilExpired());

        // ~ Post-state check ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue);

        assertEq(address(revStreamETH).balance, amountRevenue);
        assertEq(address(revDistributor).balance, 0);

        // ~ expired is skimmed ~

        vm.prank(ADMIN);
        revStreamETH.skimExpiredRevenue();

        // ~ Post-state check 2 ~

        assertEq(revStreamETH.claimable(JOE), 0);
        assertEq(revStreamETH.expiredRevenue(), 0);

        assertEq(address(revStreamETH).balance, 0);
        assertEq(address(revDistributor).balance, amountRevenue);
    }

    function test_mainDeployment_revStreamETH_skimExpiredRevenue_multiple() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        rwaToken.mintFor(JOE, amount);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(revStreamETH.timeUntilExpired()-3);

        // ~ Pre-state check ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue * 3);
        assertEq(revStreamETH.expiredRevenue(), 0);

        assertEq(address(revStreamETH).balance, amountRevenue * 3);
        assertEq(address(revDistributor).balance, 0);

        // ~ Skip to expiration 1 ~

        skip(1); // first deposit is now expired

        // ~ Post-state check 1 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue * 3);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue);

        assertEq(address(revStreamETH).balance, amountRevenue * 3);
        assertEq(address(revDistributor).balance, 0);

        // ~ Skip to expiration 2 ~

        vm.prank(ADMIN);
        revStreamETH.skimExpiredRevenue();

        skip(1); // second deposit + first is now expired

        // ~ Post-state check 2 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue * 2);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue);

        assertEq(address(revStreamETH).balance, amountRevenue * 2);
        assertEq(address(revDistributor).balance, amountRevenue);

        // ~ Skip to expiration 3 ~

        vm.prank(ADMIN);
        revStreamETH.skimExpiredRevenue();

        skip(1); // third deposit + second + first is now expired

        // ~ Post-state check 3 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue);
        assertEq(revStreamETH.expiredRevenue(), amountRevenue);

        assertEq(address(revStreamETH).balance, amountRevenue);
        assertEq(address(revDistributor).balance, amountRevenue * 2);

        // ~ Admin skims last bit of revenue ~

        vm.prank(ADMIN);
        revStreamETH.skimExpiredRevenue();

        // ~ Post-state check 4 ~

        assertEq(revStreamETH.claimable(JOE), 0);
        assertEq(revStreamETH.expiredRevenue(), 0);

        assertEq(address(revStreamETH).balance, 0);
        assertEq(address(revDistributor).balance, amountRevenue * 3);
    }

    function test_mainDeployment_revStreamETH_skimExpiredRevenue_multipleHolders() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 3_000 ether;
        uint256 duration = (1 * 30 days);

        rwaToken.mintFor(JOE, amount);
        rwaToken.mintFor(BOB, amount);
        rwaToken.mintFor(ALICE, amount);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint Bob veRWA token
        vm.startPrank(BOB);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            BOB,
            uint208(rwaToken.balanceOf(BOB)),
            duration
        );
        vm.stopPrank();

        // mint Alice veRWA token
        vm.startPrank(ALICE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            ALICE,
            uint208(rwaToken.balanceOf(ALICE)),
            duration
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        skip(1);

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        skip(1); // skip to avoid future lookup error

        // ~ Pre-state check ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue*2/3);
        assertEq(revStreamETH.claimable(BOB), amountRevenue*2/3);
        assertEq(revStreamETH.claimable(ALICE), amountRevenue*2/3);
        assertEq(revStreamETH.expiredRevenue(), 0);

        // ~ Joe and Bob claim their revenue ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        vm.prank(BOB);
        revStreamETH.claimETH(BOB);
        
        // ~ Skip to expiration ~

        skip(revStreamETH.timeUntilExpired());

        // ~ Post-state check 1 ~

        uint256 unclaimed = amountRevenue*2/3;

        assertEq(revStreamETH.claimable(JOE), 0);
        assertEq(revStreamETH.claimable(BOB), 0);
        assertEq(revStreamETH.claimable(ALICE), unclaimed);
        assertEq(revStreamETH.expiredRevenue(), unclaimed);

        // ~ Another deposit ~

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStreamETH.depositETH{value: amountRevenue}();

        skip(1); // skip to avoid future lookup error

        // ~ Post-state check 2 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue/3);
        assertEq(revStreamETH.claimable(BOB), amountRevenue/3);
        assertEq(revStreamETH.claimable(ALICE), amountRevenue/3 + unclaimed);
        assertEq(revStreamETH.expiredRevenue(), unclaimed);

        // ~ Expired revenue is skimmed ~

        vm.prank(ADMIN);
        revStreamETH.skimExpiredRevenue();

        skip(1);

        // ~ Post-state check 3 ~

        assertEq(revStreamETH.claimable(JOE), amountRevenue/3);
        assertEq(revStreamETH.claimable(BOB), amountRevenue/3);
        assertEq(revStreamETH.claimable(ALICE), amountRevenue/3);
        assertEq(revStreamETH.expiredRevenue(), 0);

        // ~ All claim ~

        vm.prank(JOE);
        revStreamETH.claimETH(JOE);

        vm.prank(BOB);
        revStreamETH.claimETH(BOB);

        vm.prank(ALICE);
        revStreamETH.claimETH(ALICE);
    }

    // ~ ExactInputWrapper test ~

    function test_mainDeployment_exactInputWrapper_exactInputForETH() public {

        // ~ Config ~

        uint256 amountUSDC = 10 * 10**6;

        // deal some USDC
        deal(address(UNREAL_USDC), address(this), amountUSDC);

        // get quote
        (uint256 quoteETHFromUSDC,,,) = quoter.quoteExactInput(
            abi.encodePacked(address(UNREAL_USDC), uint24(1000), address(UNREAL_DAI), uint24(1000), WETH),
            amountUSDC
        );

        emit log_named_uint("ETH quoted", quoteETHFromUSDC);

        IERC20(address(UNREAL_USDC)).approve(address(exactInputWrapper), amountUSDC);
        exactInputWrapper.exactInputForETH(
            abi.encodePacked(address(UNREAL_USDC), uint24(1000), address(UNREAL_DAI), uint24(1000), WETH),
            address(UNREAL_USDC),
            address(this),
            block.timestamp + 100,
            amountUSDC,
            quoteETHFromUSDC
        );
    }

    function test_mainDeployment_convertRewardTokenBatch_exactInputForETH() public {

        // ~ Config ~

        vm.prank(ADMIN);
        revDistributor.addRevenueToken(UNREAL_USDC);

        uint256 amountIn = 50 ether;
        uint256 amountUSDC = 10 * 10**6;

        rwaToken.mintFor(JOE, amountIn);
        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountIn);
        veRWA.mint(
            JOE,
            uint208(amountIn),
            (1 * 30 days)
        );
        vm.stopPrank();

        // deal some USDC
        deal(address(UNREAL_USDC), address(revDistributor), amountUSDC);

        // get quote
        (uint256 quoteETHFromUSDC,,,) = quoter.quoteExactInput(
            abi.encodePacked(address(UNREAL_USDC), uint24(1000), address(UNREAL_DAI), uint24(1000), WETH),
            amountUSDC
        );

        uint256 preBal = address(revStreamETH).balance;

        // ~ Pre-state check ~

        assertEq(IERC20(UNREAL_USDC).balanceOf(address(revDistributor)), amountUSDC);
        assertEq(address(revStreamETH).balance, preBal);

        // ~ Execute RevenueDistributor::convertRewardToken ~

        vm.startPrank(ADMIN);
        revDistributor.convertRewardToken(
            address(UNREAL_USDC),
            amountUSDC,
            address(exactInputWrapper),
            abi.encodeWithSignature(
                "exactInputForETH(bytes,address,address,uint256,uint256,uint256)",
                abi.encodePacked(address(UNREAL_USDC), uint24(1000), address(UNREAL_DAI), uint24(1000), WETH),
                address(UNREAL_USDC),
                address(revDistributor),
                block.timestamp + 100,
                amountUSDC,
                quoteETHFromUSDC
            )
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(IERC20(UNREAL_USDC).balanceOf(address(revDistributor)), 0);
        assertGt(address(revStreamETH).balance, preBal);
    }
}