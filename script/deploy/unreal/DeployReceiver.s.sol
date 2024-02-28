// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RWAToken } from "../../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../../../src/governance/VotingEscrowVesting.sol";
import { RealReceiver } from "../../../src/RealReceiver.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/DeployReceiver.s.sol:DeployReceiver --broadcast --legacy --verify
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

/**
 * @title DeployReceiver
 * @author Chase Brown
 * @notice This script deploys RealReceiver to UNREAL Testnet.
 */
contract DeployReceiver is DeployUtility {

    // ~ Contracts ~

    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;

    // ~ Variables ~

    address public passiveIncomeNFTV1 = MUMBAI_PI_NFT;
    address public tngblToken = MUMBAI_TNGBL_TOKEN;

    address public localEndpoint = UNREAL_LZ_ENDPOINT_V1;
    uint16 public sourceEndpointId = MUMBAI_CHAINID;

    address public ADMIN = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");

        veRWA = RWAVotingEscrow(payable(_loadDeploymentAddress("RWAVotingEscrow")));
        vesting = VotingEscrowVesting(payable(_loadDeploymentAddress("VotingEscrowVesting")));
        rwaToken = RWAToken(payable(_loadDeploymentAddress("RWAToken")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy RealReceiver ~

        // Deploy RealReceiver
        RealReceiver realReceiver = new RealReceiver(address(localEndpoint));

        // Deploy proxy for realReceiver
        ERC1967Proxy realReceiverProxy = new ERC1967Proxy(
            address(realReceiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(sourceEndpointId),
                address(veRWA),
                address(rwaToken),
                ADMIN
            )
        );
        realReceiver = RealReceiver(address(realReceiverProxy));
        _saveDeploymentAddress("RealReceiver", address(realReceiver));


        // ~ Config ~

        RWAVotingEscrow(address(veRWA)).updateEndpointReceiver(address(realReceiver));

        RWAToken(address(rwaToken)).setVotingEscrowRWA(address(veRWA)); // for RWAVotingEscrow:migrate
        RWAToken(address(rwaToken)).setReceiver(address(realReceiver)); // for RWAVotingEscrow:migrate

        // TODO: Set Receiver on RWAToken
        // TODO: Set trusted remote address via CrossChainMigrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));
        // TODO: Also set trusted remote on receiver
        RealReceiver(address(realReceiver)).setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(0x7b480d219F68dA5c630534de8bFD0219Bd7BCFaB));


        // ~ Logs ~

        console2.log("1a. Real Receiver  =", address(realReceiver));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   1a. Real Receiver  = 0xa0e1eDED3Bfe0D5A19ba83e0bC66DE267D7BAE32
//   1b. Implementation = 0xDFA3E667E30F0b086a368F8bAA28602783746eE7