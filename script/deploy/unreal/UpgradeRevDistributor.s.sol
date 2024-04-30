// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/UpgradeRevDistributor.s.sol:UpgradeRevDistributor --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/RevenueDistributor.sol:RevenueDistributor \
    --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title UpgradeRevDistributor
 * @author Chase Brown
 * @notice This script deploys a new RevenueDistributor contract and upgrades the current contract on unreal.
 */
contract UpgradeRevDistributor is DeployUtility {

    // ~ Contracts ~
    RevenueDistributor public revDistributor;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");

        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        RevenueDistributor newRevDistributor = new RevenueDistributor();
        revDistributor.upgradeToAndCall(address(newRevDistributor), "");

        vm.stopBroadcast();
    }
}