// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RealReceiver } from "../../../src/RealReceiver.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/UpgradeRealReceiver.s.sol:UpgradeRealReceiver --broadcast --verify --legacy --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

/**
 * @title UpgradeRealReceiver
 * @author Chase Brown
 * @notice This script deploys a new RealReceiver contract and upgrades the current contract on unreal.
 */
contract UpgradeRealReceiver is DeployUtility {

    // ~ Contracts ~
    RealReceiver public receiver;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");
        receiver = RealReceiver(payable(_loadDeploymentAddress("RealReceiver")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        RealReceiver newImplementation = new RealReceiver(UNREAL_LZ_ENDPOINT_V1);
        receiver.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();
    }
}