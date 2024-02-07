// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/mumbai/UpgradeMigrator.s.sol:UpgradeMigrator --broadcast

/**
 * @title UpgradeMigrator
 * @author Chase Brown
 * @notice This script upgrades the CrossChainMigrator on Mumbai
 */
contract UpgradeMigrator is Script {

    // ~ Contracts ~

    // core contracts
    CrossChainMigrator public migrator;

    address public currentMigratorProxy = 0xBDCA54AFA8B032c428b7b044903A6402E7aa3D3a;

    // ~ Variables ~

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy CrossChainMigrator
        migrator = new CrossChainMigrator(address(0)); // todo add endpoint

        // TODO upgrade current
        CrossChainMigrator(currentMigratorProxy).upgradeToAndCall(
            address(migrator),
            bytes("")
        );

        vm.stopBroadcast();
    }
}