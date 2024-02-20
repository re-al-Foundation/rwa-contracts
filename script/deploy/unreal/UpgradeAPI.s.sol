// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/UpgradeAPI.s.sol:UpgradeAPI --broadcast --legacy --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

/**
 * @title UpgradeAPI
 * @author Chase Brown
 * @notice This script upgrades the VotingEscrowRWAAPI on UNREAL Testnet.
 */
contract UpgradeAPI is Script {

    // ~ Contracts ~

    VotingEscrowRWAAPI public api = VotingEscrowRWAAPI(0x70805d3Fa831608eED291Be797f726231f15316a);
    VotingEscrowRWAAPI public newApi;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy api
        newApi = new VotingEscrowRWAAPI();

        // Upgrade
        api.upgradeToAndCall(address(newApi), "");

        // ~ Logs ~

        console2.log("API imp", address(newApi));

        vm.stopBroadcast();
    }
}

// == Logs ==
//  API imp 0xf977E9Fe917C0E693Eb80141258c520D7a981B75