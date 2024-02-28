// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RoyaltyHandler } from "../../../src/RoyaltyHandler.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/UpgradeRoyaltyHandler.s.sol:UpgradeRoyaltyHandler --broadcast --verify --legacy --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

/**
 * @title UpgradeRoyaltyHandler
 * @author Chase Brown
 * @notice This script deploys a new RoyaltyHandler contract and upgrades the current contract on unreal.
 */
contract UpgradeRoyaltyHandler is DeployUtility {

    // ~ Contracts ~
    RoyaltyHandler public royaltyHandler;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");
        royaltyHandler = RoyaltyHandler(payable(_loadDeploymentAddress("RoyaltyHandler")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        RoyaltyHandler newImplementation = new RoyaltyHandler();
        royaltyHandler.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();
    }
}