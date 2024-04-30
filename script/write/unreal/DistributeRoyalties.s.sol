// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// local imports
import { RoyaltyHandler } from "../../../src/RoyaltyHandler.sol";
import { RWAToken } from "../../../src/RWAToken.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/DistributeRoyalties.s.sol:DistributeRoyalties --broadcast --legacy -vvvv

/**
 * @title DistributeRoyalties
 * @author Chase Brown
 * @notice This script converts and distributes revenue from the revenue distributor.
 */
contract DistributeRoyalties is DeployUtility {

    // ~ Contracts ~

    RoyaltyHandler public royaltyHandler;
    RWAToken public rwaToken;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");

        royaltyHandler = RoyaltyHandler(payable(_loadDeploymentAddress("RoyaltyHandler")));
        rwaToken = RWAToken(payable(_loadDeploymentAddress("RWAToken")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        uint256 bal = IERC20(address(rwaToken)).balanceOf(address(royaltyHandler));
        console2.log("RWA Balance", bal);

        royaltyHandler.setPercentageDeviation(1000);

        royaltyHandler.distributeRoyalties();

        vm.stopBroadcast();
    }
}