// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RoyaltyHandler } from "../../../src/RoyaltyHandler.sol";
import { RWAToken } from "../../../src/RWAToken.sol";
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/write/unreal/UpdatePearlAddresses.s.sol:UpdatePearlAddresses --broadcast --legacy \
    --gas-estimate-multiplier 200 -vvvv
*/

/**
 * @title UpdatePearlAddresses
 * @author Chase Brown
 * @notice This script updates setters on the RoyaltyHandler on Pearl
 */
contract UpdatePearlAddresses is DeployUtility {

    // ~ Contracts ~

    // core contracts
    RoyaltyHandler public royaltyHandler;
    RWAToken public rwaToken;
    RevenueDistributor public revDistributor;

    // ~ Variables ~

    address public WETH9 = 0x0C68a3C11FB3550e50a4ed8403e873D367A8E361; // Note: If changes, redeploy RoyaltyHandler
    address public SWAP_ROUTER = 0x0a42599e0840aa292C76620dC6d4DAfF23DB5236;
    address public QUOTER = 0x6B6dA57BA5E77Ed5504Fe778449056fbb18020D5;
    address public BOXMANAGER = 0xce777A3e9D2F6B80D4Ff2297346Ef572636d8FCE;

    address public USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    address public PEARL = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;

    address public passiveIncomeNFTV1 = POLYGON_PI_NFT;
    address public tngblToken = POLYGON_TNGBL_TOKEN;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
        _setUp("unreal");

        royaltyHandler = RoyaltyHandler(payable(_loadDeploymentAddress("RoyaltyHandler")));
        console2.log("royaltyHandler address fetched", address(royaltyHandler));

        rwaToken = RWAToken(payable(_loadDeploymentAddress("RWAToken")));
        console2.log("RWAToken address fetched", address(rwaToken));

        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
        console2.log("revDistributor address fetched", address(revDistributor));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        royaltyHandler.setALMBoxManager(BOXMANAGER);
        royaltyHandler.setPearl(PEARL);
        royaltyHandler.setQuoter(QUOTER);
        royaltyHandler.setSwapRouter(SWAP_ROUTER);

        //revDistributor.addRevenueToken(USTB);

        rwaToken.setRoyaltyHandler(address(royaltyHandler));

        revDistributor.setSelectorForTarget(SWAP_ROUTER, bytes4(keccak256("multicall(bytes[])")));
        rwaToken.excludeFromFees(SWAP_ROUTER, true);

        vm.stopBroadcast();
    }
}