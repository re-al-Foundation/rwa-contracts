// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/mainnet/UpgradeAPI.s.sol:UpgradeAPI --broadcast --legacy \
    --gas-estimate-multiplier 600 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \ 
    src/helpers/VotingEscrowRWAAPI.sol:VotingEscrowRWAAPI \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title UpgradeAPI
 * @author Chase Brown
 * @notice This script upgrades the VotingEscrowRWAAPI on re.al.
 */
contract UpgradeAPI is Script {

    // ~ Contracts ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy api
        VotingEscrowRWAAPI newApi = new VotingEscrowRWAAPI();

        // TODO Upgrade
        // api.upgradeToAndCall(address(newApi), "");

        // ~ Logs ~

        console2.log("API imp", address(newApi));

        vm.stopBroadcast();
    }
}