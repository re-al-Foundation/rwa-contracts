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

/// @dev To run: forge script script/deploy/goerli/DeployReceivers.s.sol:DeployReceivers --broadcast --verify
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 5 --watch src/Contract.sol:Contract --verifier etherscan

/**
 * @title DeployReceivers
 * @author Chase Brown
 * @notice This script deploys RealReceiver to Goerli.
 */
contract DeployReceivers is Script {

    // ~ Contracts ~

    // core contracts
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;

    RealReceiver public receiver;
    
    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;

    ERC1967Proxy public receiverProxy;

    // ~ Variables ~

    address public passiveIncomeNFTV1 = MUMBAI_PI_NFT;
    address public tngblToken = MUMBAI_TNGBL_TOKEN;

    address public localEndpoint = GEORLI_LZ_ENDPOINT_V1;
    uint16 public sourceEndpointId = MUMBAI_CHAINID;

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public GOERLI_RPC_URL = vm.envString("GOERLI_RPC_URL");

    bytes32 public constant MINTER_ROLE = keccak256("MINTER");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER");

    function setUp() public {
        vm.createSelectFork(GOERLI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy RWA Token ~

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN,
                address(0), // uniswap router
                address(0)  // revenue distributor
            )
        );


        // ~ Deploy Vesting ~

        // Deploy vesting contract
        vesting = new VotingEscrowVesting();

        // Deploy proxy for vesting contract
        vestingProxy = new ERC1967Proxy(
            address(vesting),
            abi.encodeWithSelector(VotingEscrowVesting.initialize.selector,
                ADMIN // admin address
            )
        );


        // ~ Deploy VERWA ~

        // Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();

        // Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaTokenProxy), // RWA token
                address(vestingProxy),  // votingEscrowVesting
                address(0), // local LZ endpoint
                ADMIN // admin address
            )
        );


        // ~ Deploy RealReceiver ~

        // (7) Deploy RealReceiver
        receiver = new RealReceiver(address(localEndpoint));

        // (8) Deploy proxy for receiver
        receiverProxy = new ERC1967Proxy(
            address(receiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                // todo chainId
                uint16(sourceEndpointId),
                address(veRWAProxy),
                ADMIN
            )
        );


        // ~ Config ~

        RWAVotingEscrow(address(veRWAProxy)).updateEndpointReceiver(address(receiverProxy));

        VotingEscrowVesting(address(vestingProxy)).setVotingEscrowContract(address(veRWAProxy));

        RWAToken(payable(address(rwaTokenProxy))).grantRole(MINTER_ROLE, address(veRWAProxy)); // for RWAVotingEscrow:migrate
        RWAToken(payable(address(rwaTokenProxy))).grantRole(MINTER_ROLE, address(receiverProxy)); // for RWAVotingEscrow:migrate
        RWAToken(payable(address(rwaTokenProxy))).grantRole(BURNER_ROLE, address(veRWAProxy)); // for RWAVotingEscrow:migrate


        // ~ Logs ~

        console2.log("1a. RWAToken              =", address(rwaTokenProxy));
        console2.log("1b. RWAToken (Imp)        =", address(rwaToken));

        console2.log("2a. VotingEscrowRWA       =", address(veRWAProxy));
        console2.log("2b. VotingEscrowRWA (Imp) =", address(veRWA));

        console2.log("3a. RealReceiver       =", address(receiverProxy));
        console2.log("3b. RealReceiver (Imp) =", address(receiver));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   1a. RWAToken              = 0xC17E501826EeECcE5454176691087972af02209e ✅
//   1b. RWAToken (Imp)        = 0x35991B2Cfba8B94E7c7B5F2454C0f1b7249CA77E ✅

//   2a. VotingEscrowRWA       = 0x54C3CCA61660Dd6AfC93133672bA60c66AE22c55 ✅
//   2b. VotingEscrowRWA (Imp) = 0xC1259DF66477f6CD85Ec4cAa642485bdA0F9FC80 ✅

//   3a. RealReceiver       = 0x6408340f4967f47E1d2Fa2C4D17f78EeE1aB8A39 ✅
//   3b. RealReceiver (Imp) = 0xD86ee67328cDACa103b82774FF0b131D03dfdFB5 ✅