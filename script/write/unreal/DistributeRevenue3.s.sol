// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
// token
import { RWAToken } from "../../../src/RWAToken.sol";
// revenue management
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";
// migration
import { RealReceiver } from "../../../src/RealReceiver.sol";
// mocks
import { LZEndpointMock } from "../../../test/utils/LZEndpointMock.sol";
import { MarketplaceMock } from "../../../test/utils/MarketplaceMock.sol";
// v1
import { PassiveIncomeNFT } from "../../../src/refs/PassiveIncomeNFT.sol";
import { TangibleERC20Mock } from "../../../test/utils/TangibleERC20Mock.sol";
// wrapper contract
import { ExactInputWrapper } from "../../../src/helpers/ExactInputWrapper.sol";
// uniswap
import { IUniswapV2Router02 } from "../../../src/interfaces/IUniswapV2Router02.sol";

import { ISwapRouter } from "../../../src/interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "../../../src/interfaces/IQuoterV2.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/DistributeRevenue3.s.sol:DistributeRevenue3 --broadcast --legacy -vvvv

/**
 * @title DistributeRevenue3
 * @author Chase Brown
 * @notice This script converts and distributes revenue from the revenue distributor.
 */
contract DistributeRevenue3 is Script {

    // ~ Contracts ~

    RWAToken public rwaToken = RWAToken(payable(UNREAL_RWA_TOKEN));
    RevenueDistributor public revDistributor = RevenueDistributor(payable(UNREAL_REV_DISTRIBUTOR));
    RevenueStreamETH public revStreamETH;

    ExactInputWrapper public exactInputWrapper = ExactInputWrapper(payable(0xD86ee67328cDACa103b82774FF0b131D03dfdFB5));

    TangibleERC20Mock public DAI = TangibleERC20Mock(UNREAL_DAI);
    TangibleERC20Mock public USDC = TangibleERC20Mock(UNREAL_USDC);

    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(UNREAL_UNIV2_ROUTER);

    IQuoterV2 public quoter = IQuoterV2(UNREAL_QUOTERV2);

    address public multicallInterface = 0x92D676A4917aF4c19fF0450c90471D454Ac423fc;

    // ~ Variables ~

    address public WETH;

    uint256 internal amountRWA;
    uint256 internal amountDAI;
    uint256 internal amountUSDC;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    //bytes4 public selector_swapExactTokensForETH =
    //   bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));
    bytes4 public selector_exactInput = 
        bytes4(keccak256("multicall(bytes[])"));
    bytes4 public selector_exactInputWrapper = 
        bytes4(keccak256("exactInputForETH(bytes,address,address,uint256,uint256,uint256)"));

    struct Call {
        address target;
        uint256 gasLimit;
        bytes callData;
    }

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        WETH = uniswapV2Router.WETH();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // get amounts
        amountRWA  = rwaToken.balanceOf(address(revDistributor));
        amountDAI  = 10 ether; //DAI.balanceOf(address(revDistributor));
        amountUSDC = 10 * 10**6; //USDC.balanceOf(address(revDistributor));

        console2.log("amount RWA", amountRWA);
        console2.log("amount DAI", amountDAI);
        console2.log("amount USDC", amountUSDC);

        // ~ Build DAI -> ETH Multicall ~

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(DAI),
            tokenOut: WETH,
            fee: 1000,
            recipient: address(UNREAL_SWAP_ROUTER),
            deadline: block.timestamp + 300,
            amountIn: amountDAI,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data1_DAI = 
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

        bytes memory data2_DAI =
            abi.encodeWithSignature(
                "unwrapWETH9(uint256,address)",
                0, // minimum out
                address(revDistributor)
            );
        
        bytes[] memory multicallData_DAI_ETH = new bytes[](2);
        multicallData_DAI_ETH[0] = data1_DAI;
        multicallData_DAI_ETH[1] = data2_DAI;

        // ~ Build USDC -> DAI -> ETH Multicall ~

        // IQuoterV2.QuoteExactInputSingleParams memory quoteParams = IQuoterV2.QuoteExactInputSingleParams({
        //     tokenIn: address(USDC),
        //     tokenOut: address(DAI),
        //     amountIn: amountUSDC,
        //     fee: 1000,
        //     sqrtPriceLimitX96: 0
        // });

        //(uint256 quoteDAIFromUSDC,,,) = quoter.quoteExactInputSingle(quoteParams);

        (uint256 quoteETHFromUSDC,,,) = quoter.quoteExactInput(
            abi.encodePacked(USDC, uint24(1000), DAI, uint24(1000), WETH),
            amountUSDC
        );

        console2.log("quote", quoteETHFromUSDC);

        // USDC -> DAI
        bytes memory callForUSDC = 
            abi.encodeWithSignature(
                "exactInputForETH(bytes,address,address,uint256,uint256,uint256)",
                abi.encodePacked(USDC, uint24(1000), DAI, uint24(1000), WETH),
                address(UNREAL_USDC),
                address(revDistributor),
                block.timestamp + 300,
                amountUSDC,
                0
            );


        // ~ Build RWA -> ETH call ~

        address[] memory path_RWA_ETH = new address[](2);
        path_RWA_ETH[0] = address(rwaToken);
        path_RWA_ETH[1] = WETH;


        // ~ Build convertRewardToken call ~

        address[] memory tokens = new address[](3);
        tokens[0] = address(rwaToken);
        tokens[1] = address(DAI);
        tokens[2] = address(USDC);

        address[] memory targets = new address[](3);
        targets[0] = UNREAL_UNIV2_ROUTER;
        targets[1] = UNREAL_SWAP_ROUTER;
        targets[2] = address(exactInputWrapper);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountRWA;
        amounts[1] = amountDAI;
        amounts[2] = amountUSDC;

        bytes[] memory data = new bytes[](3);
        data[0] = 
            abi.encodeWithSignature(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                amountRWA,
                0,
                path_RWA_ETH,
                address(revDistributor),
                block.timestamp + 300
            );
        data[1] = 
            abi.encodeWithSignature("multicall(bytes[])", multicallData_DAI_ETH);
        data[2] = 
            callForUSDC;

        // Execute batch conversion
        uint256[] memory amountsOut = revDistributor.convertRewardTokenBatch(
            tokens,
            amounts,
            targets,
            data
        );

        console2.log("amount ETH from RWA",  amountsOut[0]);
        console2.log("amount ETH from DAI",  amountsOut[1]);
        console2.log("amount ETH from USDC", amountsOut[2]);

        vm.stopBroadcast();
    }
}