// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { Delegator } from "../../../src/governance/Delegator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/mainnet/UpgradeDelegator.s.sol:UpgradeDelegator --broadcast --legacy --gas-estimate-multiplier 800 --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch src/governance/Delegator.sol:Delegator --verifier blockscout --verifier-url https://explorer.re.al//api

/**
 * @title UpgradeDelegator
 * @author Chase Brown
 * @notice This script upgrades the Delegator on re.al.
 */
contract UpgradeDelegator is Script {

    // ~ Contracts ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        vm.createSelectFork(vm.envString("REAL_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        new Delegator();

        // TODO: Upgrade implementation

        vm.stopBroadcast();
    }
}