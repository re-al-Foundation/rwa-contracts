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

/// @dev To run: forge script script/deploy/sepolia/DeployReceiver.s.sol:DeployReceiver --broadcast --verify
/// @dev To verify manually: forge verify-contract <CONTRACT_ADDRESS> --chain-id 5 --watch src/Contract.sol:Contract --verifier etherscan

/**
 * @title DeployReceiver
 * @author Chase Brown
 * @notice This script deploys RealReceiver to SEPOLIA Testnet.
 */
contract DeployReceiver is Script {

    // ~ Contracts ~

    // core contracts
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;

    RealReceiver public realReceiver;
    
    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;

    ERC1967Proxy public realReceiverProxy;

    // ~ Variables ~

    address public passiveIncomeNFTV1 = MUMBAI_PI_NFT;
    address public tngblToken = MUMBAI_TNGBL_TOKEN;

    address public localEndpoint = SEPOLIA_LZ_ENDPOINT_V1;
    uint16 public sourceEndpointId = MUMBAI_CHAINID;

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");

    bytes32 public constant MINTER_ROLE = keccak256("MINTER");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER");

    function setUp() public {
        vm.createSelectFork(SEPOLIA_RPC_URL);
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
        realReceiver = new RealReceiver(address(localEndpoint));

        // (8) Deploy proxy for realReceiver
        realReceiverProxy = new ERC1967Proxy(
            address(realReceiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(sourceEndpointId),
                address(veRWAProxy),
                address(rwaTokenProxy),
                ADMIN
            )
        );


        // ~ Config ~

        RWAVotingEscrow(address(veRWAProxy)).updateEndpointReceiver(address(realReceiverProxy));

        VotingEscrowVesting(address(vestingProxy)).setVotingEscrowContract(address(veRWAProxy));

        RWAToken(payable(address(rwaTokenProxy))).grantRole(MINTER_ROLE, address(veRWAProxy)); // for RWAVotingEscrow:migrate
        RWAToken(payable(address(rwaTokenProxy))).grantRole(MINTER_ROLE, address(realReceiverProxy)); // for RWAVotingEscrow:migrate
        RWAToken(payable(address(rwaTokenProxy))).grantRole(BURNER_ROLE, address(veRWAProxy)); // for RWAVotingEscrow:migrate


        // ~ Logs ~

        console2.log("1a. RWAToken              =", address(rwaTokenProxy));
        console2.log("1b. RWAToken (Imp)        =", address(rwaToken));

        console2.log("2a. VotingEscrowRWA       =", address(veRWAProxy));
        console2.log("2b. VotingEscrowRWA (Imp) =", address(veRWA));

        console2.log("3a. RealReceiver       =", address(realReceiverProxy));
        console2.log("3b. RealReceiver (Imp) =", address(realReceiver));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   1a. RWAToken              = 0xAf960b9B057f59c68e55Ff9aC29966d9bf62b71B
//   1b. RWAToken (Imp)        = 0x95A3Af3e65A669792d5AbD2e058C4EcC34A98eBb
//   2a. VotingEscrowRWA       = 0x297670562a8BcfACBe5c30BBAC5ca7062ac7f652
//   2b. VotingEscrowRWA (Imp) = 0x400f6195fd33E22DFB551F9e65AACf7BA4557040
//   3a. RealReceiver       = 0x5aE75eb64478067e537F0534Fc6cE4dAf464E84d
//   3b. RealReceiver (Imp) = 0x898e32fe2E33A2ad44ffc272bdD33D5199E95b4D