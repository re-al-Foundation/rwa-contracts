// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

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
contract SetTrustedRemote is Script {

    // ~ Contracts ~

    // core contracts
    CrossChainMigrator public migrator = CrossChainMigrator(0xD42F6Ce9fc98440c518A01749d6fB526CAd52E11);

    uint16 public remoteEndpointId = UNREAL_CHAINID;
    address public receiver = 0x36b6240FD63D5A4fb095AbF7cC8476659C76071C;

    // ~ Variables ~

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        migrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));

        vm.stopBroadcast();
    }
}