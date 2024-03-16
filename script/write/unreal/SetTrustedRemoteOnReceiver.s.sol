// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { RealReceiver } from "../../../src/RealReceiver.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/SetTrustedRemoteOnReceiver.s.sol:SetTrustedRemoteOnReceiver --broadcast --legacy -vvvv

/**
 * @title SetTrustedRemoteOnReceiver
 * @author Chase Brown
 * @notice This script deploys RealReceiver to Bsc Testnet.
 */
contract SetTrustedRemoteOnReceiver is DeployUtility {

    RealReceiver public realReceiver;
    address public migrator;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
        _setUp("unreal");
        realReceiver = RealReceiver(_loadDeploymentAddress("RealReceiver"));
        migrator = _loadDeploymentAddress("CrossChainMigrator");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        realReceiver.setTrustedRemoteAddress(MUMBAI_CHAINID, abi.encodePacked(address(migrator)));

        vm.stopBroadcast();
    }
}