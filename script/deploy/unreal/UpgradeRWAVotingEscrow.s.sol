// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/UpgradeRWAVotingEscrow.s.sol:UpgradeRWAVotingEscrow --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/governance/RWAVotingEscrow.sol:RWAVotingEscrow \
    --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title UpgradeRWAVotingEscrow
 * @author Chase Brown
 * @notice This script deploys a new RWAVotingEscrow contract and upgrades the current contract on unreal.
 */
contract UpgradeRWAVotingEscrow is DeployUtility {

    // ~ Contracts ~
    RWAVotingEscrow public revDistributor;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");

        revDistributor = RWAVotingEscrow(payable(_loadDeploymentAddress("RWAVotingEscrow")));
        console2.log("Fetched RWAVotingEscrow", address(revDistributor));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        RWAVotingEscrow newRWAve = new RWAVotingEscrow();
        revDistributor.upgradeToAndCall(address(newRWAve), "");

        vm.stopBroadcast();
    }
}