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

/// @dev To run: forge script script/write/mumbai/SetTrustedRemote.s.sol:SetTrustedRemote --broadcast -vvvv

/**
 * @title SetTrustedRemote
 * @author Chase Brown
 * @notice This script calls setTrustedRemoteAddress on the Mumbai Migator contract
 */
contract SetTrustedRemote is DeployUtility {

    // ~ Contracts ~

    // core contracts
    CrossChainMigrator public migrator;

    uint16 public remoteEndpointId = UNREAL_LZ_CHAIN_ID_V1;
    address public receiver;

    // ~ Variables ~

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
        _setUp("unreal");
        receiver = _loadDeploymentAddress("RealReceiver");
        migrator = CrossChainMigrator(_loadDeploymentAddress("CrossChainMigrator"));

        console2.log("fetched receiver", address(receiver));
        console2.log("fetched migrator", address(migrator));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        migrator.setReceiver(receiver);
        migrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));

        vm.stopBroadcast();
    }
}