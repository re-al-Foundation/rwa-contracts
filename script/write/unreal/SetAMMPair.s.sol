// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { RWAToken } from "../../../src/RWAToken.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/SetAMMPair.s.sol:SetAMMPair --broadcast --legacy -vvvv --gas-estimate-multiplier 300

/**
 * @title SetAMMPair
 * @author Chase Brown
 * @notice This script deploys RWAToken to Bsc Testnet.
 */
contract SetAMMPair is DeployUtility {

    RWAToken public rwaToken;

    address public pool = 0x8fb7c11A6573970E8eBBE15D276BA55B7a2e6DF3;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
        _setUp("unreal");
        rwaToken = RWAToken(_loadDeploymentAddress("RWAToken"));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        rwaToken.setAutomatedMarketMakerPair(pool, true);

        vm.stopBroadcast();
    }
}