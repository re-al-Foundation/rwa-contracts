// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// local imports
import { DelegateFactoryMock } from "../../../test/mocks/DelegateFactoryMock.sol";
import { RWAVotingEscrowMock } from "../../../test/mocks/RWAVotingEscrowMock.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployMocks.s.sol:DeployMocks --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title DeployMocks
 */
contract DeployMocks is Script {

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        new DelegateFactoryMock();
        new RWAVotingEscrowMock();

        vm.stopBroadcast();
    }
}