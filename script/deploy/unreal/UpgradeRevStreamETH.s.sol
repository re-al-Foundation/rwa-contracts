// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/UpgradeRevStreamETH.s.sol:UpgradeRevStreamETH --broadcast --verify --legacy -vvvv

/**
 * @title UpgradeRevStreamETH
 * @author Chase Brown
 * @notice This script deploys a new RevenueStreamETH contract and upgrades the current contract on unreal.
 */
contract UpgradeRevStreamETH is Script {

    // ~ Contracts ~
    RevenueStreamETH public oldRevStreamETH = RevenueStreamETH(payable(0x541c058d0D7Ab8474Ea10fb090677FaD992256d9));
    RevenueStreamETH public newRevStreamETH;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        newRevStreamETH = new RevenueStreamETH();
        console2.log("new RevStreamETH Implementation", address(newRevStreamETH));

        oldRevStreamETH.upgradeToAndCall(address(newRevStreamETH), "");

        vm.stopBroadcast();
    }
}