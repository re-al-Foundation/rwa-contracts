// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol"; 

// local imports
import { RevenueStream } from "../src/RevenueStream.sol";
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../src/RevenueDistributor.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";

import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";

// local helper imports
import { Utility } from "./utils/Utility.sol";
import "./utils/Constants.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
 
/**
 * @title RevenueDistributorTest
 * @author @chasebrownn
 * @notice This test file contains the basic unit tests for the RevenueDistributor contract.
 */
contract RevenueDistributorTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    RevenueStream public revStream;
    RevenueStreamETH public revStreamETH;
    RevenueDistributor public revDistributor;
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;

    ERC20Mock public mockRevToken1;
    ERC20Mock public mockRevToken2;

    // proxies
    ERC1967Proxy public revStreamETHProxy;
    ERC1967Proxy public revDistributorProxy;
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;

    // ~ Variables ~

    address public WETH;
    bytes4 public selector_swapExactTokensForETH;

    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        WETH = IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).WETH();

        selector_swapExactTokensForETH =
            bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));

        // ~ Deployment ~

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN
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

        // Deploy revDistributor contract
        revDistributor = new RevenueDistributor();

        // Deploy proxy for revDistributor
        revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                ADMIN,
                address(0),
                address(rwaToken),
                address(veRWA)
            )
        );
        revDistributor = RevenueDistributor(payable(address(revDistributorProxy)));


        // ~ Revenue Stream ETH deployment ~

        // Deploy revStreamETH contract
        revStreamETH = new RevenueStreamETH();

        // Deply proxy for revStreamETH
        revStreamETHProxy = new ERC1967Proxy(
            address(revStreamETH),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                address(veRWA),
                ADMIN
            )
        );
        revStreamETH = RevenueStreamETH(payable(address(revStreamETHProxy)));


        // Deploy mock rev token 1
        mockRevToken1 = new ERC20Mock();
        // Deploy mock rev token 2
        mockRevToken2 = new ERC20Mock();


        // ~ Config ~

        // RevenueDistributor config
        vm.startPrank(ADMIN);
        revDistributor.setDistributor(GELATO, true);
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));
        revDistributor.addRevenueToken(address(mockRevToken1));
        revDistributor.addRevenueToken(address(mockRevToken2));
        revDistributor.addRevenueToken(address(rwaToken));
        revDistributor.setSelectorForTarget(MUMBAI_UNIV2_ROUTER, selector_swapExactTokensForETH);
        vm.stopPrank();

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(this)); // for testing
        vm.stopPrank();

        // Exclude necessary addresses from RWA fees.
        vm.startPrank(ADMIN);
        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(address(revDistributor), true);
        rwaToken.excludeFromFees(JOE, true);
        vm.stopPrank();

        // Mint Joe $RWA tokens
        rwaToken.mintFor(JOE, 1_000 ether);

        // ~ Create Pools ~

        // pair 1: ETH / mockToken1
        // pair 2: ETH / mockToken2
        // pair 3: RWA / mockToken1
        // pair 4: RWA / mockToken2
        // pair 5: RWA / ETH

        // pair 1

        uint256 ETH_DEPOSIT = 10 ether;
        uint256 TOKEN_DEPOSIT = 100_000 ether;

        mockRevToken1.mint(address(this), TOKEN_DEPOSIT);
        mockRevToken1.approve(address(MUMBAI_UNIV2_ROUTER), TOKEN_DEPOSIT);

        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).addLiquidityETH{value: ETH_DEPOSIT}(
            address(mockRevToken1),
            TOKEN_DEPOSIT,
            TOKEN_DEPOSIT,
            ETH_DEPOSIT,
            address(this),
            block.timestamp
        );

        // pair 2

        ETH_DEPOSIT = 10 ether;
        TOKEN_DEPOSIT = 100_000 ether;

        mockRevToken2.mint(address(this), TOKEN_DEPOSIT);
        mockRevToken2.approve(address(MUMBAI_UNIV2_ROUTER), TOKEN_DEPOSIT);

        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).addLiquidityETH{value: ETH_DEPOSIT}(
            address(mockRevToken2),
            TOKEN_DEPOSIT,
            TOKEN_DEPOSIT,
            ETH_DEPOSIT,
            address(this),
            block.timestamp
        );

        // pair 5

        ETH_DEPOSIT = 10 ether;
        uint256 RWA_DEPOSIT = 100_000 ether;

        rwaToken.mintFor(address(this), RWA_DEPOSIT);
        rwaToken.approve(address(MUMBAI_UNIV2_ROUTER), RWA_DEPOSIT);

        IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).addLiquidityETH{value: ETH_DEPOSIT}(
            address(rwaToken),
            RWA_DEPOSIT,
            RWA_DEPOSIT,
            ETH_DEPOSIT,
            address(this),
            block.timestamp
        );
    }


    // -------
    // Utility
    // -------
    
    /// @dev Returns the amount of ETH tokens quoted for `amount` tokens.
    function _getQuoteETH(address tokenIn, uint256 amount) internal view returns (uint256) {
        address[] memory path = new address[](2);

        path[0] = tokenIn;
        path[1] = WETH;

        uint256[] memory amounts = 
            IUniswapV2Router02(MUMBAI_UNIV2_ROUTER).getAmountsOut(amount, path);

        return amounts[1];
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @dev Verifies initial state of RevenueDistributor contract.
    function test_revDist_init_state() public {
        assertEq(revDistributor.owner(), ADMIN);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev This unit test verifies proper state changes when RevenueDistributor::convertRewardToken is executed.
    function test_revDist_convertRewardToken_single() public {

        // ~ Config ~

        uint256 amountIn = 100 ether;
        mockRevToken1.mint(address(revDistributor), amountIn);

        uint256 quoteOut = _getQuoteETH(address(mockRevToken1), amountIn);
        uint256 preBal = address(revStreamETH).balance;

        uint256 amountETH = 2 ether;
        deal(address(revDistributor), amountETH);

        address[] memory path = new address[](2);
        path[0] = address(mockRevToken1);
        path[1] = WETH;

        // ~ Pre-state check ~

        assertEq(mockRevToken1.balanceOf(address(revDistributor)), amountIn);
        assertEq(address(revStreamETH).balance, preBal);

        // ~ Execute RevenueDistributor::convertRewardToken ~

        vm.startPrank(ADMIN);
        uint256 amountOut = revDistributor.convertRewardToken(
            address(mockRevToken1),
            amountIn,
            MUMBAI_UNIV2_ROUTER,
            abi.encodeWithSignature(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                amountIn,
                quoteOut,
                path,
                address(revDistributor),
                block.timestamp + 100
            )
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(amountOut, quoteOut);

        assertEq(mockRevToken1.balanceOf(address(revDistributor)), 0);
        assertEq(address(revStreamETH).balance, preBal + quoteOut + amountETH);
    }

    /// @dev This unit test verifies proper state changes when RevenueDistributor::convertRewardTokenBatch is executed.
    function test_revDist_convertRewardTokenBatch() public {

        // ~ Config ~

        uint256 amountIn = 100 ether;

        mockRevToken1.mint(address(revDistributor), amountIn);
        mockRevToken2.mint(address(revDistributor), amountIn);
        rwaToken.mintFor(address(revDistributor), amountIn);

        uint256 quoteOut1 = _getQuoteETH(address(mockRevToken1), amountIn);
        uint256 quoteOut2 = _getQuoteETH(address(mockRevToken2), amountIn);
        uint256 quoteOut3 = _getQuoteETH(address(rwaToken), amountIn);

        address[] memory path1 = new address[](2);
        path1[0] = address(mockRevToken1);
        path1[1] = WETH;
        address[] memory path2 = new address[](2);
        path2[0] = address(mockRevToken2);
        path2[1] = WETH;
        address[] memory path3 = new address[](2);
        path3[0] = address(rwaToken);
        path3[1] = WETH;

        address[] memory tokens = new address[](3);
        tokens[0] = address(mockRevToken1);
        tokens[1] = address(mockRevToken2);
        tokens[2] = address(rwaToken);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
        amounts[2] = amountIn;

        address[] memory targets = new address[](3);
        targets[0] = MUMBAI_UNIV2_ROUTER;
        targets[1] = MUMBAI_UNIV2_ROUTER;
        targets[2] = MUMBAI_UNIV2_ROUTER;

        bytes[] memory data = new bytes[](3);
        data[0] = 
            abi.encodeWithSignature(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                amountIn,
                quoteOut1,
                path1,
                address(revDistributor),
                block.timestamp + 100
            );
        data[1] = 
            abi.encodeWithSignature(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                amountIn,
                quoteOut2,
                path2,
                address(revDistributor),
                block.timestamp + 100
            );
        data[2] = 
            abi.encodeWithSignature(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                amountIn,
                quoteOut3,
                path3,
                address(revDistributor),
                block.timestamp + 100
            );

        // ~ Pre-state check ~

        assertEq(mockRevToken1.balanceOf(address(revDistributor)), amountIn);
        assertEq(mockRevToken2.balanceOf(address(revDistributor)), amountIn);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amountIn);
        assertEq(address(revStreamETH).balance, 0);

        // ~ Execute RevenueDistributor::convertRewardToken ~

        vm.startPrank(ADMIN);
        uint256[] memory amountsOut = revDistributor.convertRewardTokenBatch(
            tokens,
            amounts,
            targets,
            data
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(amountsOut[0], quoteOut1);
        assertEq(amountsOut[1], quoteOut2);
        assertEq(amountsOut[2], quoteOut3);

        assertEq(mockRevToken1.balanceOf(address(revDistributor)), 0);
        assertEq(mockRevToken2.balanceOf(address(revDistributor)), 0);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);
        assertEq(address(revStreamETH).balance, quoteOut1 + quoteOut2 + quoteOut3);
    }

    function test_revDist_addRevenueToken() public {

        // ~ Config ~
        
        address newToken = address(222);

        // ~ Pre-state check ~

        assertEq(revDistributor.isRevToken(newToken), false);

        address[] memory revTokens = revDistributor.getRevenueTokensArray();
        assertEq(revTokens.length, 3);
        assertEq(revTokens[0], address(mockRevToken1));
        assertEq(revTokens[1], address(mockRevToken2));
        assertEq(revTokens[2], address(rwaToken));

        // ~ Execute addRevenueToken ~

        vm.prank(ADMIN);
        revDistributor.addRevenueToken(newToken);

        // ~ Post-state check ~

        assertEq(revDistributor.isRevToken(newToken), true);

        revTokens = revDistributor.getRevenueTokensArray();
        assertEq(revTokens.length, 4);
        assertEq(revTokens[0], address(mockRevToken1));
        assertEq(revTokens[1], address(mockRevToken2));
        assertEq(revTokens[2], address(rwaToken));
        assertEq(revTokens[3], newToken);
    }

    function test_revDist_removeRevenueToken() public {

        // ~ Pre-state check ~

        assertEq(revDistributor.isRevToken(address(mockRevToken1)), true);

        address[] memory revTokens = revDistributor.getRevenueTokensArray();
        assertEq(revTokens.length, 3);
        assertEq(revTokens[0], address(mockRevToken1));
        assertEq(revTokens[1], address(mockRevToken2));
        assertEq(revTokens[2], address(rwaToken));

        // ~ Execute addRevenueToken ~

        vm.prank(ADMIN);
        revDistributor.removeRevenueToken(address(mockRevToken1));

        // ~ Post-state check ~

        assertEq(revDistributor.isRevToken(address(mockRevToken1)), false);

        revTokens = revDistributor.getRevenueTokensArray();
        assertEq(revTokens.length, 2);
        assertEq(revTokens[0], address(rwaToken));
        assertEq(revTokens[1], address(mockRevToken2));
    }
    
}