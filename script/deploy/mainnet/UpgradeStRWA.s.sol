// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { stRWA as StakedRWA } from "../../../src/staking/stRWA.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/mainnet/UpgradeStRWA.s.sol:UpgradeStRWA --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \ 
    src/StakedRWA.sol:StakedRWA \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title UpgradeStRWA
 * @author Chase Brown
 * @notice This script deploys a new StakedRWA contract and upgrades the current contract on unreal.
 */
contract UpgradeStRWA is DeployUtility {

    // ~ Contracts ~
    StakedRWA public stRWAToken;
    address public rwaToken;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");

        stRWAToken = StakedRWA(payable(_loadDeploymentAddress("stRWA")));
        rwaToken = _loadDeploymentAddress("RWAToken");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        StakedRWA newImplementation = new StakedRWA(block.chainid, REAL_LZ_ENDPOINT_V1, rwaToken);
        stRWAToken.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();
    }
}