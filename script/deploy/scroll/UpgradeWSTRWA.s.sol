// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { WrappedstRWASatellite } from "../../../src/staking/WrappedstRWASatellite.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/scroll/UpgradeWSTRWA.s.sol:UpgradeWSTRWA --broadcast --verify -vvvv
*/

/**
 * @title UpgradeWSTRWA
 * @author Chase Brown
 * @notice This script deploys a new StakedRWA contract and upgrades the current contract on unreal.
 */
contract UpgradeWSTRWA is DeployUtility {

    // ~ Contracts ~
    WrappedstRWASatellite public wstRWAToken;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        vm.createSelectFork(vm.envString("SCROLL_RPC_URL"));
        _setUp("scroll");

        wstRWAToken = WrappedstRWASatellite(payable(_loadDeploymentAddress("wstRWA")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        wstRWAToken.upgradeToAndCall(address(new WrappedstRWASatellite(111188, SCROLL_LZ_ENDPOINT_V1)), "");

        vm.stopBroadcast();
    }
}