// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// local imports
import { RealReceiver } from "../../../src/RealReceiver.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/sepolia/SetTrustedRemoteOnReceiver.s.sol:SetTrustedRemoteOnReceiver --broadcast

/**
 * @title SetTrustedRemoteOnReceiver
 * @author Chase Brown
 * @notice This script deploys RealReceiver to Bsc Testnet.
 */
contract SetTrustedRemoteOnReceiver is Script {

    // ~ Contracts ~

    RealReceiver public realReceiver = RealReceiver(0x5aE75eb64478067e537F0534Fc6cE4dAf464E84d);

    // ~ Variables ~

    uint16 public sourceEndpointId = MUMBAI_CHAINID;

    address public migrator = 0xD42F6Ce9fc98440c518A01749d6fB526CAd52E11;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");

    function setUp() public {
        vm.createSelectFork(SEPOLIA_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        realReceiver.setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(migrator));

        vm.stopBroadcast();
    }
}