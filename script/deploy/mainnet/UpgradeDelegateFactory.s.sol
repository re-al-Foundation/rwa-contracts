// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { DelegateFactory } from "../../../src/governance/DelegateFactory.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/mainnet/UpgradeDelegateFactory.s.sol:UpgradeDelegateFactory --broadcast --legacy --gas-estimate-multiplier 400 --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch src/governance/DelegateFactory.sol:DelegateFactory --verifier blockscout --verifier-url https://explorer.re.al//api

/**
 * @title UpgradeDelegateFactory
 * @author Chase Brown
 * @notice This script upgrades the DelegateFactory on re.al mainnet.
 */
contract UpgradeDelegateFactory is Script {

    // ~ Contracts ~

    //DelegateFactory public api = DelegateFactory(0x4Bc715a61dF515944907C8173782ea83d196D0c9);

    function setUp() public {
        vm.createSelectFork(vm.envString("REAL_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Deploy api
        DelegateFactory newDelegateFactory = new DelegateFactory();

        // Upgrade
        //api.upgradeToAndCall(address(newDelegateFactory), "");

        vm.stopBroadcast();
    }
}