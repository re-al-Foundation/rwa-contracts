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
    forge script script/deploy/mainnet/UpgradeRevDist.s.sol:UpgradeRevDistributor --broadcast --legacy \
    --gas-estimate-multiplier 600 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \ 
    src/RevenueDistributor.sol:RevenueDistributor \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title UpgradeRevDistributor
 * @author Chase Brown
 * @notice This script deploys a new RevenueDistributor contract and upgrades the current contract on re.al.
 */
contract UpgradeRevDistributor is DeployUtility {

    // ~ Contracts ~
    RevenueDistributor public revDistributor;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");

        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        RevenueDistributor newRevDistributor = new RevenueDistributor();
        //TODO: upgradeToAndCall(address(newRevDistributor), "");

        vm.stopBroadcast();
    }
}