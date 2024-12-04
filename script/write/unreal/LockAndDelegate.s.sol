// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// local imports
import { RWAToken } from "../../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
import { DelegateFactory } from "../../../src/governance/DelegateFactory.sol";
import { Delegator } from "../../../src/governance/Delegator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/unreal/LockAndDelegate.s.sol:LockAndDelegate --broadcast --legacy --gas-estimate-multiplier 600 -vvvv 

/**
 * @title LockAndDelegate
 * @author Chase Brown
 * @notice This script converts and distributes revenue from the revenue distributor.
 */
contract LockAndDelegate is DeployUtility {

    // ~ Contracts ~

    RWAToken public rwaToken;
    RWAVotingEscrow public votingEscrow;
    DelegateFactory public delegateFactory;

    // ~ Vars ~

    address public constant DELEGATEE = 0x54792B36bf490FC53aC56dB33fD3953B56DF6baF;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        vm.createSelectFork(vm.envString("UNREAL_RPC_URL"));
        _setUp("unreal");

        rwaToken = RWAToken(payable(_loadDeploymentAddress("RWAToken")));
        votingEscrow = RWAVotingEscrow(payable(_loadDeploymentAddress("RWAVotingEscrow")));
        delegateFactory = DelegateFactory(payable(_loadDeploymentAddress("DelegateFactory")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        uint256 amount = 1 ether;

        // lock RWA
        rwaToken.approve(address(votingEscrow), amount);
        uint256 tokenId = votingEscrow.mint(
            DEPLOYER_ADDRESS,
            uint208(amount),
            votingEscrow.MAX_VESTING_DURATION()
        );

        // delegate tokenId to Milica via factory
        votingEscrow.approve(address(delegateFactory), tokenId);
        Delegator delegator = Delegator(delegateFactory.deployDelegator(
            tokenId,
            DELEGATEE,
            30 * 1 days
        ));
        
        // set claimable to true
        delegator.setClaimable(true);

        vm.stopBroadcast();
    }
}