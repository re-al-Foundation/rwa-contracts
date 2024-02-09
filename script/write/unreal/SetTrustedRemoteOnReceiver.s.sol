// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// local imports
import { RealReceiver } from "../../../src/RealReceiver.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/SetTrustedRemoteOnReceiver.s.sol:SetTrustedRemoteOnReceiver --broadcast --legacy -vvvv

/**
 * @title SetTrustedRemoteOnReceiver
 * @author Chase Brown
 * @notice This script deploys RealReceiver to Bsc Testnet.
 */
contract SetTrustedRemoteOnReceiver is Script {

    // ~ Contracts ~

    RealReceiver public realReceiver = RealReceiver(0x36b6240FD63D5A4fb095AbF7cC8476659C76071C); // unreal

    // ~ Variables ~

    uint16 public sourceEndpointId = MUMBAI_CHAINID;

    address public migrator = 0x7b480d219F68dA5c630534de8bFD0219Bd7BCFaB;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        realReceiver.setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(migrator));

        vm.stopBroadcast();
    }
}