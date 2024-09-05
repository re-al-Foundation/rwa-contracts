// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/mainnet/UpgradeRevStreamETH.s.sol:UpgradeRevStreamETH --broadcast --legacy \
    --gas-estimate-multiplier 600 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \
    src/RevenueStreamETH.sol:RevenueStreamETH \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title UpgradeRevStreamETH
 * @author Chase Brown
 * @notice This script deploys a new RevenueStreamETH contract and upgrades the current contract on re.al.
 */
contract UpgradeRevStreamETH is DeployUtility {

    // ~ Contracts ~
    RevenueStreamETH public revStreamETH;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
        _setUp("re.al");

        revStreamETH = RevenueStreamETH(payable(_loadDeploymentAddress("RevenueStreamETH")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        address newRevStreamETH = address(new RevenueStreamETH());
        //TODO: upgrade

        console2.log("Address", newRevStreamETH);

        vm.stopBroadcast();
    }
}