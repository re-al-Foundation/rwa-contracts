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

    address public constant SWAP_ROUTER = 0xa752C9Cd89FE0F9D07c8dC79A7564b45F904b344;

    bytes4 public selector_exactInputSingle = 
        bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
    bytes4 public selector_exactInputSingleFeeOnTransfer = 
        bytes4(keccak256("exactInputSingleFeeOnTransfer((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
    bytes4 public selector_exactInput = 
        bytes4(keccak256("exactInput((bytes,address,uint256,uint256,uint256))"));
    bytes4 public selector_exactInputFeeOnTransfer = 
        bytes4(keccak256("exactInputFeeOnTransfer((bytes,address,uint256,uint256,uint256))"));


    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");

        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
        console2.log("Fetched RevenueDistributor", address(revDistributor));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        RevenueDistributor newRevDistributor = new RevenueDistributor();
        revDistributor.upgradeToAndCall(address(newRevDistributor), "");

        revDistributor.setSelectorForTarget(SWAP_ROUTER, selector_exactInputSingle, true);
        revDistributor.setSelectorForTarget(SWAP_ROUTER, selector_exactInputSingleFeeOnTransfer, true);
        revDistributor.setSelectorForTarget(SWAP_ROUTER, selector_exactInput, true);
        revDistributor.setSelectorForTarget(SWAP_ROUTER, selector_exactInputFeeOnTransfer, true);

        vm.stopBroadcast();
    }
}