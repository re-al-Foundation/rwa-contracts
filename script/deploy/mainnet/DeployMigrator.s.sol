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

/** 
    @dev To run: 
    forge script script/deploy/mainnet/DeployMigrator.s.sol:DeployMigrator --broadcast --verify -vvvv
*/

/**
 * @title DeployMigrator
 * @author Chase Brown
 * @notice This script deploys CrossChainMigrator to Re.al
 */
contract DeployMigrator is DeployUtility {

    address public realReceiver;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
    address public adminAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        vm.createSelectFork(POLYGON_RPC_URL);
        _setUp("re.al");
        realReceiver = _loadDeploymentAddress("RealReceiver");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy CrossChainMigrator
        CrossChainMigrator migrator = new CrossChainMigrator(POLYGON_LZ_ENDPOINT_V1);
        // Deploy proxy for migrator
        ERC1967Proxy migratorProxy = new ERC1967Proxy(
            address(migrator),
            abi.encodeWithSelector(CrossChainMigrator.initialize.selector,
                POLYGON_PI_NFT,        // LOCAL ADDRESS 1 -> 3,3+ NFT
                POLYGON_PI_CALC,       // piCalc NFT address
                POLYGON_TNGBL_TOKEN,   // LOCAL ADDRESS 2 -> $TNGBL
                realReceiver,         // REMOTE ADDRESS 1 -> RECEIVER
                REAL_LZ_CHAIN_ID_V1,  // REMOTE CHAIN ID -> now endpoint ID
                adminAddress
            )
        );
        console2.log("migrator", address(migratorProxy));
        migrator = CrossChainMigrator(address(migratorProxy));

        migrator.setMinDstGas(REAL_LZ_CHAIN_ID_V1, 0, 200000);
        migrator.setMinDstGas(REAL_LZ_CHAIN_ID_V1, 1, 200000);
        migrator.setMinDstGas(REAL_LZ_CHAIN_ID_V1, 2, 200000);
        migrator.setTrustedRemoteAddress(REAL_LZ_CHAIN_ID_V1, abi.encodePacked(realReceiver));
        migrator.toggleMigration();

        _setUp("polygon");
        _saveDeploymentAddress("CrossChainMigrator", address(migrator));

        vm.stopBroadcast();
    }
}