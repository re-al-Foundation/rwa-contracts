// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/read/unreal/GetNFTData.s.sol:GetNFTData --broadcast --legacy -vvvv

/**
 * @title GetNFTData
 * @author Chase Brown
 * @notice This script reads getNFTsOfOwnerWithData from VotingEscrowRWAAPI on Unreal.
 */
contract GetNFTData is Script {

    // ~ Contracts ~

    VotingEscrowRWAAPI public api = VotingEscrowRWAAPI(0x70805d3Fa831608eED291Be797f726231f15316a);

    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        VotingEscrowRWAAPI.TokenData[] memory tokenData = api.getNFTsOfOwnerWithData(0xBc0Af260d262a982297ddAa96715Ef6c31536C24);

        vm.stopBroadcast();
    }
}