// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/DeployUtilityTest.s.sol:DeployUtilityTest --broadcast --legacy -vvvv

/**
 * @title DeployUtilityTest
 * @author Chase Brown
 */
contract DeployUtilityTest is DeployUtility {

    // ~ Contracts ~

    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy VotingEscrowRWAAPI ~

        // load address, log
        address temp = _loadDeploymentAddress("DelegateFactory");
        console2.log("address", temp);

        // save address
        _saveDeploymentAddress("RealReceiver", address(0));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   API = 0xEE08C27028409669534d2D7c990D3b9B13DF03c5