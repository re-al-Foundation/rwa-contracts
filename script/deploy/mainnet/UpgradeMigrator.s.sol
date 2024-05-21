// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/mainnet/UpgradeMigrator.s.sol:UpgradeMigrator --broadcast --verify --verifier etherscan -vvvv
/// @dev To verify: forge verify-contract <CONTRACT_ADDRESS> --chain-id 80001 --watch src/CrossChainMigrator.sol:CrossChainMigrator --verifier etherscan --constructor-args $(cast abi-encode "constructor(address)" 0x3c2269811836af69497E5F486A85D7316753cf62)

/**
 * @title UpgradeMigrator
 * @author Chase Brown
 * @notice This script deploys CrossChainMigrator to Polygon
 */
contract UpgradeMigrator is DeployUtility {

    // ~ Contracts ~

    // core contracts
    CrossChainMigrator public migrator;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");


    function setUp() public {
        vm.createSelectFork(POLYGON_RPC_URL);
        _setUp("polygon");
        migrator = CrossChainMigrator(_loadDeploymentAddress("CrossChainMigrator"));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy new migrator implementation
        CrossChainMigrator newMigrator = new CrossChainMigrator(POLYGON_LZ_ENDPOINT_V1);

        // set new implementation
        migrator.upgradeToAndCall(address(newMigrator), "");

        // ~ Logs ~

        console2.log("New Migrator Imp =", address(newMigrator));

        vm.stopBroadcast();
    }
}