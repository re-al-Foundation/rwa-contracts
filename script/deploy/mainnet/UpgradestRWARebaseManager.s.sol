// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { TokenSilo } from "../../../src/staking/TokenSilo.sol";
import { stRWARebaseManager } from "../../../src/staking/stRWARebaseManager.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/mainnet/UpgradestRWARebaseManager.s.sol:UpgradestRWARebaseManager --broadcast --legacy \
    --gas-estimate-multiplier 800 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \ 
    src/staking/stRWARebaseManager.sol:stRWARebaseManager \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title UpgradestRWARebaseManager
 * @author Chase Brown
 * @notice This script deploys a new stRWARebaseManager contract and upgrades the current contract on mainnet.
 */
contract UpgradestRWARebaseManager is DeployUtility {

    // ~ Contracts ~

    address public tokenSilo;
    address public stRWA;
    stRWARebaseManager public rebaseManager;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");

        tokenSilo = _loadDeploymentAddress("TokenSilo");
        stRWA = _loadDeploymentAddress("stRWA");
        rebaseManager = stRWARebaseManager(_loadDeploymentAddress("stRWARebaseManager"));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        rebaseManager.upgradeToAndCall(address(new stRWARebaseManager(address(stRWA), address(tokenSilo))), "");

        vm.stopBroadcast();
    }
}