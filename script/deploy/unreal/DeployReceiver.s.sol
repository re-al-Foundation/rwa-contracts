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

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployReceiver.s.sol:DeployReceiver --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
*/

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

    address public ADMIN = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
        _setUp("unreal");

        veRWA = RWAVotingEscrow(payable(_loadDeploymentAddress("RWAVotingEscrow")));
        vesting = VotingEscrowVesting(payable(_loadDeploymentAddress("VotingEscrowVesting")));
        rwaToken = RWAToken(payable(_loadDeploymentAddress("RWAToken")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy RealReceiver ~

        // Deploy RealReceiver
        RealReceiver realReceiver = new RealReceiver(address(UNREAL_LZ_ENDPOINT_V1));

        // Deploy proxy for realReceiver
        ERC1967Proxy realReceiverProxy = new ERC1967Proxy(
            address(realReceiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(MUMBAI_CHAINID),
                address(veRWA),
                address(rwaToken),
                ADMIN
            )
        );
        realReceiver = RealReceiver(address(realReceiverProxy));
        _saveDeploymentAddress("RealReceiver", address(realReceiver));


        // ~ Config ~

        RWAVotingEscrow(address(veRWA)).updateEndpointReceiver(address(realReceiver));

        RWAToken(address(rwaToken)).setReceiver(address(realReceiver));

        // TODO: Set trusted remote address via CrossChainMigrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));
        // TODO: Also set trusted remote on receiver via RealReceiver.setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(address(crossChainMigrator)));

        // ~ Logs ~

        console2.log("Real Receiver  =", address(realReceiver));

        vm.stopBroadcast();
    }
}