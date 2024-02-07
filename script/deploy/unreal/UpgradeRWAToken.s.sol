// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RWAToken } from "../../../src/RWAToken.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/UpgradeRWAToken.s.sol:UpgradeRWAToken --broadcast --verify --legacy -vvvv

/**
 * @title UpgradeRWAToken
 * @author Chase Brown
 * @notice This script deploys a new RWAToken contract and upgrades the current contract on unreal.
 */
contract UpgradeRWAToken is Script {

    // ~ Contracts ~
    RWAToken public oldRWAToken = RWAToken(payable(0x909Fd75Ce23a7e61787FE2763652935F92116461));
    RWAToken public newRWAToken;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        newRWAToken = new RWAToken();
        console2.log("new RWAToken Implementation", address(newRWAToken));

        oldRWAToken.upgradeToAndCall(address(newRWAToken), "");

        vm.stopBroadcast();
    }
}