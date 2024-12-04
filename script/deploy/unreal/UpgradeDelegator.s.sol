// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { DelegateFactory } from "../../../src/governance/DelegateFactory.sol";
import { Delegator } from "../../../src/governance/Delegator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/UpgradeDelegator.s.sol:UpgradeDelegator --broadcast --legacy --gas-estimate-multiplier 200 --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

/**
 * @title UpgradeDelegator
 * @author Chase Brown
 * @notice This script upgrades the Delegator on UNREAL Testnet.
 */
contract UpgradeDelegator is Script {

    // ~ Contracts ~

    DelegateFactory public delegateFactory = DelegateFactory(0x8A59e74a793214251Bc4dfC8c211Ecc00F77a422);

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy new Delegator implementation upgrade beacon
        delegateFactory.updateDelegatorImplementation(address(new Delegator()));

        vm.stopBroadcast();
    }
}