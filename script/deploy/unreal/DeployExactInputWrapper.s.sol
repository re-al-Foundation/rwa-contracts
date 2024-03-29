// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { ExactInputWrapper } from "../../../src/helpers/ExactInputWrapper.sol";
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/DeployExactInputWrapper.s.sol:DeployExactInputWrapper --broadcast --legacy --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

/**
 * @title DeployExactInputWrapper
 * @author Chase Brown
 * @notice This script deploys ExactInputWrapper to UNREAL Testnet.
 */
contract DeployExactInputWrapper is DeployUtility {

    // ~ Contracts ~

    // core contracts
    address public router = payable(0xa752C9Cd89FE0F9D07c8dC79A7564b45F904b344);
    address public WETH = payable(UNREAL_WETH);

    RevenueDistributor public revDistributor;

    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    bytes4 public selector_exactInputWrapper = 
        bytes4(keccak256("exactInputForETH(bytes,address,address,uint256,uint256,uint256)"));

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");
        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy ExactInputWrapper ~

        // Deploy wrapper
        ExactInputWrapper wrapper = new ExactInputWrapper(
            router,
            WETH
        );

        // set as target on RevDist
        revDistributor.setSelectorForTarget(address(wrapper), selector_exactInputWrapper, true);

        // ~ Logs ~

        _saveDeploymentAddress("ExactInputWrapper", address(wrapper));
        console2.log("wrapper =", address(wrapper));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   wrapper = 0xfC80C26088131029991d6c2eFb26928Bcf6ef7c5