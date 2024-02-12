// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/DeployAPI.s.sol:DeployAPI --broadcast --legacy --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

/**
 * @title DeployAPI
 * @author Chase Brown
 * @notice This script deploys VotingEscrowRWAAPI to UNREAL Testnet.
 */
contract DeployAPI is Script {

    // ~ Contracts ~

    // core contracts
    address public veRWA = payable(0x6fa3d2CB3dEBE19e10778F3C3b95A6cDF911fC5B);
    address public vesting = payable(0xEE1643c7ED4e195893025df09E757Cc526F757F9);
    address public revStream = payable(0xeDfe244aBf03999DdAEE52E2D3E61d27517708a8);

    VotingEscrowRWAAPI public api;
    ERC1967Proxy public apiProxy;

    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy VotingEscrowRWAAPI ~

        // Deploy api
        api = new VotingEscrowRWAAPI();

        // Deploy proxy for api
        apiProxy = new ERC1967Proxy(
            address(api),
            abi.encodeWithSelector(VotingEscrowRWAAPI.initialize.selector,
                DEPLOYER_ADDRESS, // admin
                address(veRWA),
                address(vesting),
                address(revStream)
            )
        );
        api = VotingEscrowRWAAPI(address(apiProxy));


        // ~ Config ~

        // ~ Logs ~

        console2.log("API =", address(api));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   API = 0x70805d3Fa831608eED291Be797f726231f15316a