// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { TokenSilo } from "../../../src/staking/TokenSilo.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/mainnet/UpgradeTokenSilo.s.sol:UpgradeTokenSilo --broadcast --legacy \
    --gas-estimate-multiplier 800 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \ 
    src/TokenSilo.sol:TokenSilo \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title UpgradeTokenSilo
 * @author Chase Brown
 * @notice This script deploys a new TokenSilo contract and upgrades the current contract on unreal.
 */
contract UpgradeTokenSilo is DeployUtility {

    // ~ Contracts ~

    TokenSilo public tokenSilo;

    // ~ Variables ~

    address public stRWA;
    address public rwaVotingEscrow;
    address public revStream;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");

        tokenSilo = TokenSilo(payable(_loadDeploymentAddress("TokenSilo")));
        stRWA = _loadDeploymentAddress("stRWA");
        rwaVotingEscrow = _loadDeploymentAddress("RWAVotingEscrow");
        revStream = _loadDeploymentAddress("RevenueStreamETH");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        tokenSilo.upgradeToAndCall(address(new TokenSilo(address(stRWA), address(rwaVotingEscrow), address(revStream), REAL_WREETH)), "");

        vm.stopBroadcast();
    }
}