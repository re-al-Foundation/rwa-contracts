// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/DeployAPI.s.sol:DeployAPI --broadcast --legacy --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

/**
 * @title DeployAPI
 * @author Chase Brown
 * @notice This script deploys VotingEscrowRWAAPI to UNREAL Testnet.
 */
contract DeployAPI is DeployUtility {

    // ~ Contracts ~

    // core contracts
    address public veRWA;
    address public vesting;
    address public revStream;

    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");

        veRWA = payable(_loadDeploymentAddress("RWAVotingEscrow"));
        vesting = payable(_loadDeploymentAddress("VotingEscrowVesting"));
        revStream = payable(_loadDeploymentAddress("RevenueStreamETH"));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy VotingEscrowRWAAPI ~

        // Deploy api
        VotingEscrowRWAAPI api = new VotingEscrowRWAAPI();

        // Deploy proxy for api
        ERC1967Proxy apiProxy = new ERC1967Proxy(
            address(api),
            abi.encodeWithSelector(VotingEscrowRWAAPI.initialize.selector,
                DEPLOYER_ADDRESS, // admin
                address(veRWA),
                address(vesting),
                address(revStream)
            )
        );
        api = VotingEscrowRWAAPI(address(apiProxy));
        _saveDeploymentAddress("API", address(api));

        // ~ Logs ~

        console2.log("API =", address(api));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   API = 0xEE08C27028409669534d2D7c990D3b9B13DF03c5