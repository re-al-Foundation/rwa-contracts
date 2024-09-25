// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RWAToken } from "../../../src/RWAToken.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: 
/// forge script script/deploy/mainnet/UpgradeRWAToken.s.sol:UpgradeRWAToken --broadcast --gas-estimate-multiplier 300 --legacy --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv
/// @dev To Verify:
/// forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch src/RWAToken.sol:RWAToken --verifier blockscout --verifier-url https://explorer.re.al//api

/**
 * @title UpgradeRWAToken
 * @author Chase Brown
 * @notice This script deploys a new RWAToken contract and upgrades the current contract on mainnet.
 */
contract UpgradeRWAToken is DeployUtility {

    // ~ Contracts ~
    RWAToken public rwaToken;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");
        rwaToken = RWAToken(_loadDeploymentAddress("RWAToken"));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        RWAToken newRWAToken = new RWAToken();
        console2.log("new RWAToken Implementation", address(newRWAToken));

        //rwaToken.upgradeToAndCall(address(newRWAToken), "");

        vm.stopBroadcast();
    }
}