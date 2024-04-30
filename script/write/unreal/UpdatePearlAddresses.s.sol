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

    address public USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    address public PEARL = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;

    bytes4 public selector_exactInputSingle = 
        bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
    bytes4 public selector_exactInputSingleFeeOnTransfer = 
        bytes4(keccak256("exactInputSingleFeeOnTransfer((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
    bytes4 public selector_exactInput = 
        bytes4(keccak256("exactInput((bytes,address,uint256,uint256,uint256))"));
    bytes4 public selector_exactInputFeeOnTransfer = 
        bytes4(keccak256("exactInputFeeOnTransfer((bytes,address,uint256,uint256,uint256))"));

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

        royaltyHandler.setALMBoxManager(UNREAL_BOX_MANAGER);
        royaltyHandler.setPearl(UNREAL_PEARL);
        royaltyHandler.setSwapRouter(UNREAL_SWAP_ROUTER);

        //revDistributor.addRevenueToken(USTB);

        //rwaToken.setRoyaltyHandler(address(royaltyHandler));

        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInputSingle, true);
        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInputSingleFeeOnTransfer, true);
        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInput, true);
        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInputFeeOnTransfer, true);
        //rwaToken.excludeFromFees(SWAP_ROUTER, true);

        vm.stopBroadcast();
    }
}