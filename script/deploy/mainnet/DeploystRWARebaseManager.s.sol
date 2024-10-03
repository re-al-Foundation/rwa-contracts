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
    forge script script/deploy/mainnet/DeploystRWARebaseManager.s.sol:DeploystRWARebaseManager --broadcast --legacy \
    --gas-estimate-multiplier 800 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \ 
    src/TokenSilo.sol:TokenSilo \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title DeploystRWARebaseManager
 * @author Chase Brown
 * @notice This script deploys a new TokenSilo contract and upgrades the current contract on unreal.
 */
contract DeploystRWARebaseManager is DeployUtility {

    // ~ Contracts ~

    TokenSilo public tokenSilo;
    address public stRWA;

    // ~ Variables ~

    address public constant SINGLE_TOKEN_PROVIDER = 0x5c8beC8D9B2FF163929389cB530d6AEe886fb3c0;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");

        tokenSilo = TokenSilo(payable(_loadDeploymentAddress("TokenSilo")));
        stRWA = _loadDeploymentAddress("stRWA");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        ERC1967Proxy rebaseManagerProxy = new ERC1967Proxy(
            address(new stRWARebaseManager(address(stRWA), address(tokenSilo))),
            abi.encodeWithSelector(stRWARebaseManager.initialize.selector,
                DEPLOYER_ADDRESS, // owner
                address(0), // pool
                address(0), // gaige
                SINGLE_TOKEN_PROVIDER // singleTokenProvider
            )
        );

        tokenSilo.setRebaseManager(address(rebaseManagerProxy));

        _saveDeploymentAddress("stRWARebaseManager", address(rebaseManagerProxy));

        vm.stopBroadcast();
    }
}