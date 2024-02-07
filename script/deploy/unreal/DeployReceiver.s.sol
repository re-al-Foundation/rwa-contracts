// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

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
contract DeployReceiver is Script {

    // ~ Contracts ~

    // core contracts
    RWAVotingEscrow public veRWA = RWAVotingEscrow(payable(0x6fa3d2CB3dEBE19e10778F3C3b95A6cDF911fC5B));
    VotingEscrowVesting public vesting = VotingEscrowVesting(payable(0xEE1643c7ED4e195893025df09E757Cc526F757F9));
    RWAToken public rwaToken = RWAToken(payable(0x909Fd75Ce23a7e61787FE2763652935F92116461));

    RealReceiver public realReceiver;
    ERC1967Proxy public realReceiverProxy;

    // ~ Variables ~

    address public passiveIncomeNFTV1 = MUMBAI_PI_NFT;
    address public tngblToken = MUMBAI_TNGBL_TOKEN;

    address public localEndpoint = UNREAL_LZ_ENDPOINT_V1;
    uint16 public sourceEndpointId = MUMBAI_CHAINID;

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    bytes32 public constant MINTER_ROLE = keccak256("MINTER");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy RealReceiver ~

        // Deploy RealReceiver
        realReceiver = new RealReceiver(address(localEndpoint));

        // Deploy proxy for realReceiver
        realReceiverProxy = new ERC1967Proxy(
            address(realReceiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(sourceEndpointId),
                address(veRWA),
                address(rwaToken),
                ADMIN
            )
        );


        // ~ Config ~

        RWAVotingEscrow(address(veRWA)).updateEndpointReceiver(address(realReceiverProxy));

        RWAToken(payable(address(rwaToken))).grantRole(MINTER_ROLE, address(veRWA)); // for RWAVotingEscrow:migrate
        RWAToken(payable(address(rwaToken))).grantRole(MINTER_ROLE, address(realReceiverProxy)); // for RWAVotingEscrow:migrate
        RWAToken(payable(address(rwaToken))).grantRole(BURNER_ROLE, address(veRWA)); // for RWAVotingEscrow:migrate

        // TODO: Set trusted remote address via CrossChainMigrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));


        // ~ Logs ~

        console2.log("1a. Real Receiver  =", address(realReceiverProxy)); // 0x36b6240FD63D5A4fb095AbF7cC8476659C76071C
        console2.log("1b. Implementation =", address(realReceiver)); // 0x1e44E0a4B8596E47E291f868A0485864AC7eE869

        vm.stopBroadcast();
    }
}