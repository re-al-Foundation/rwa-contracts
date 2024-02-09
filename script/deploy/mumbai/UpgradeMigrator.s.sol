// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/mumbai/UpgradeMigrator.s.sol:UpgradeMigrator --broadcast --verify -vvvv
/// @dev To verify: forge verify-contract <CONTRACT_ADDRESS> --chain-id 80001 --watch src/CrossChainMigrator.sol:CrossChainMigrator --verifier etherscan

/**
 * @title UpgradeMigrator
 * @author Chase Brown
 * @notice This script deploys CrossChainMigrator to Mumbai
 */
contract UpgradeMigrator is Script {

    // ~ Contracts ~

    // core contracts
    CrossChainMigrator public migrator = CrossChainMigrator(0x7b480d219F68dA5c630534de8bFD0219Bd7BCFaB);
    CrossChainMigrator public newMigrator;

    // ~ Variables ~

    address public localEndpoint = MUMBAI_LZ_ENDPOINT_V1;
    uint16 public remoteEndpointId = UNREAL_CHAINID;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy new migrator implementation
        newMigrator = new CrossChainMigrator(localEndpoint);

        // set new implementation
        migrator.upgradeToAndCall(address(newMigrator), "");

        // ~ Logs ~

        console2.log("New Migrator Imp =", address(newMigrator));

        vm.stopBroadcast();
    }
}