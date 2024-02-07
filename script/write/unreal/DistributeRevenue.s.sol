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
// uniswap
import { IUniswapV2Router02 } from "../../../src/interfaces/IUniswapV2Router02.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/DistributeRevenue.s.sol:DistributeRevenue --broadcast --legacy -vvvv

/**
 * @title DistributeRevenue
 * @author Chase Brown
 * @notice This script converts and distributes revenue from the revenue distributor.
 */
contract DistributeRevenue is Script {

    // ~ Contracts ~

    RWAToken public rwaToken = RWAToken(payable(0x909Fd75Ce23a7e61787FE2763652935F92116461));
    RevenueDistributor public revDistributor = RevenueDistributor(payable(0xa443Bf2fCA2119bFDb97Bc01096fBC4F1546c8Ae));
    RevenueStreamETH public revStreamETH = RevenueStreamETH(payable(0xeDfe244aBf03999DdAEE52E2D3E61d27517708a8));

    // ~ Variables ~

    address public WETH;
    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(UNREAL_UNIV2_ROUTER);

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    bytes4 public selector_swapExactTokensForETH =
        bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        WETH = uniswapV2Router.WETH();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        uint256 amount = rwaToken.balanceOf(address(revDistributor));
        //uint256 amount = 50 ether;

        address[] memory path = new address[](2);
        path[0] = address(rwaToken);
        path[1] = WETH;

        uint256 amountOut = revDistributor.convertRewardToken(
            address(rwaToken),
            amount,
            UNREAL_UNIV2_ROUTER,
            abi.encodeWithSignature(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                amount,
                0,
                path,
                address(revDistributor),
                block.timestamp + 300
            )
        );

        console2.log("amount ETH", amountOut);

        console2.log("total ETH bal in RevDist", address(revStreamETH).balance);

        vm.stopBroadcast();
    }
}