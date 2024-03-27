// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { RoyaltyHandler } from "../../../src/RoyaltyHandler.sol";
import { IGaugeV2Factory } from "../../../src/interfaces/IGaugeV2Factory.sol";


//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/SetGaugeOnRoyaltyHandler.s.sol:SetGaugeOnRoyaltyHandler --broadcast --legacy -vvvv --gas-estimate-multiplier 300

/**
 * @title SetGaugeOnRoyaltyHandler
 * @author Chase Brown
 * @notice This script creates a new GaugeV2ALM contract and sets it on the Royaltyhandler. @dev Needs a LiquidBox and pool deployed.
 */
contract SetGaugeOnRoyaltyHandler is DeployUtility {

    RoyaltyHandler public royaltyHandler;

    address public pool = 0x8fb7c11A6573970E8eBBE15D276BA55B7a2e6DF3;

    address public box = 0xED4F1e22371418f71f74F08897694800Db364a44;

    address public gaugeFactory = 0x518be9E09Ef51640F499055dae4186eF732FF7bF;

    address public pearlFactory = 0xDfCD83D2F29cF1E05F267927C102c0e3Dc2BD725;

    address public pearl = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;

    address public gALM;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
        _setUp("unreal");
        royaltyHandler = RoyaltyHandler(_loadDeploymentAddress("RoyaltyHandler"));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // create Gauge
        (,gALM) = IGaugeV2Factory(gaugeFactory).createGauge(
            18331,
            18331,
            pearlFactory,
            pool,
            pearl,
            DEPLOYER_ADDRESS,
            DEPLOYER_ADDRESS,
            true
        );

        // set gauge and box
        royaltyHandler.setALMBox(box);
        royaltyHandler.setGaugeV2ALM(gALM);

        vm.stopBroadcast();
    }
}