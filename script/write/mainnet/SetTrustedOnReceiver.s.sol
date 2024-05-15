// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { RealReceiver } from "../../../src/RealReceiver.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/write/mainnet/SetTrustedOnReceiver.s.sol:SetTrustedOnReceiver --broadcast --legacy \
    --gas-estimate-multiplier 600 -vvvv
*/

/**
 * @title SetTrustedOnReceiver
 * @author Chase Brown
 * @notice This script deploys RealReceiver to Bsc Testnet.
 */
contract SetTrustedOnReceiver is DeployUtility {

    RealReceiver public realReceiver;
    address public migrator;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");
        realReceiver = RealReceiver(_loadDeploymentAddress("RealReceiver"));
        _setUp("polygon");
        migrator = _loadDeploymentAddress("CrossChainMigrator");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        realReceiver.setTrustedRemoteAddress(POLYGON_CHAINID, abi.encodePacked(migrator));

        vm.stopBroadcast();
    }
}