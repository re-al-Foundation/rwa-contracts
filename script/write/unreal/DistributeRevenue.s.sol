// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
// uniswap
import { IUniswapV2Router02 } from "../../../src/interfaces/IUniswapV2Router02.sol";

import { IQuoterV2 } from "../../../src/interfaces/IQuoterV2.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/DistributeRevenue.s.sol:DistributeRevenue --broadcast --legacy -vvvv

/**
 * @title DistributeRevenue
 * @author Chase Brown
 * @notice This script converts and distributes revenue from the revenue distributor.
 */
contract DistributeRevenue is DeployUtility {

    // ~ Contracts ~

    RWAToken public rwaToken;
    RevenueDistributor public revDistributor;
    RevenueStreamETH public revStreamETH;
    IQuoterV2 public quoter = IQuoterV2(UNREAL_QUOTERV2);
    address public wrapper = payable(UNREAL_EXACTINPUTWRAPPER);

    // ~ Variables ~

    address public WETH = UNREAL_WETH;
    address public USTB = UNREAL_USTB;
    IERC20 public DAI = IERC20(UNREAL_DAI);

    address public token;

    bytes4 public selector_swapExactTokensForETH =
        bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));

    bytes4 public selector_exactInputWrapper = 
        bytes4(keccak256("exactInputForETH(bytes,address,address,uint256,uint256,uint256)"));


    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");

        rwaToken = RWAToken(payable(_loadDeploymentAddress("RWAToken")));
        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
        revStreamETH = RevenueStreamETH(payable(_loadDeploymentAddress("RevenueStreamETH")));

        token = address(DAI); // TODO
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        uint256 amount = DAI.balanceOf(address(revDistributor));
        amount = 1 ether;

        uint256 amountOut;
        if (token == address(DAI)) {
            // get quote
            (uint256 quote,,,) = quoter.quoteExactInput(
                abi.encodePacked(DAI, uint24(100), USTB, uint24(3000), WETH),
                amount
            );
            console2.log("quoted", quote);
            // perform swap
            amountOut = revDistributor.convertRewardToken(
                address(DAI),
                amount,
                address(wrapper),
                abi.encodeWithSignature(
                    "exactInputForETH(bytes,address,address,uint256,uint256,uint256)",
                    abi.encodePacked(DAI, uint24(100), USTB, uint24(3000), WETH),
                    address(DAI),
                    address(revDistributor),
                    block.timestamp + 1000,
                    amount,
                    quote
                )
            );
        }
        else if (token == address(rwaToken)) {
            // get quote
            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(rwaToken),
                tokenOut: WETH,
                amountIn: amount,
                fee: 3000,
                sqrtPriceLimitX96: 0
            });
            (uint256 quote,,,) = quoter.quoteExactInputSingle(params);
            console2.log("quoted", quote);
            // build swap
            bytes memory data1 = 
                abi.encodeWithSignature(
                    "exactInputSingleFeeOnTransfer((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                    address(rwaToken),
                    WETH,
                    3000,
                    UNREAL_SWAP_ROUTER,
                    block.timestamp + 1000,
                    amount,
                    quote,
                    0
                );
            bytes memory data2 =
                abi.encodeWithSignature(
                    "unwrapWETH9(uint256,address)",
                    quote, // minimum out
                    address(revDistributor)
                );
            bytes[] memory multicallData = new bytes[](2);
            multicallData[0] = data1;
            multicallData[1] = data2;
            // perform swap
            amountOut = revDistributor.convertRewardToken(
                address(rwaToken),
                amount,
                address(UNREAL_SWAP_ROUTER),
                abi.encodeWithSignature("multicall(bytes[])", multicallData)
            );
        }

        console2.log("amount ETH", amountOut);

        vm.stopBroadcast();
    }
}