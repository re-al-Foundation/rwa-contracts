// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// local imports
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/UpgradeRevDistributor.s.sol:UpgradeRevDistributor --broadcast --verify --legacy -vvvv

/**
 * @title UpgradeRevDistributor
 * @author Chase Brown
 * @notice This script deploys a new RevenueDistributor contract and upgrades the current contract on unreal.
 */
contract UpgradeRevDistributor is Script {

    // ~ Contracts ~
    RevenueDistributor public revDistributor = RevenueDistributor(payable(UNREAL_REV_DISTRIBUTOR));

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        RevenueDistributor newRevDistributor = new RevenueDistributor();
        revDistributor.upgradeToAndCall(address(newRevDistributor), "");

        vm.stopBroadcast();
    }
}