// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { DelegateFactory } from "../../../src/governance/DelegateFactory.sol";
import { Delegator } from "../../../src/governance/Delegator.sol";
import { RWAToken } from "../../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";

// local helper imports
import "./SampleData.sol";
import "../../utils/Utility.sol";
import "../../utils/Constants.sol";

/**
 * // -----------------------------
 * // Season 1 Points Reward Escrow
 * // -----------------------------
 * 
 * 1. Set claimable value to true on all S1 points delegators
 * 2. Allow delegatees to claim their veRWA token for X amount of days (X = 30?)
 *    - Upon claim, delegator revokes itself from the factory
 * 3. When claimable time period ends, revoke all delegator contracts
 *    - Token should go into our custody (If not claimed)
 *    - Delegator is removed from factory
 */

/**
 * @title DelegationClaimableTestUtility
 * @author @chasebrownn
 * @notice This acts as a Utility file for Delegator Claimable Tests.
 */
contract DelegationClaimableTestUtility is Utility, SampleData {

    // ~ Contracts ~

    RWAToken public constant rwaToken = RWAToken(0x4644066f535Ead0cde82D209dF78d94572fCbf14);
    RWAVotingEscrow public constant rwaVotingEscrow = RWAVotingEscrow(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);
    RevenueStreamETH public constant revStream = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);
    RevenueDistributor public constant revDist = RevenueDistributor(payable(0x7a2E4F574C0c28D6641fE78197f1b460ce5E4f6C));
    DelegateFactory public constant delegateFactory = DelegateFactory(0x4Bc715a61dF515944907C8173782ea83d196D0c9);

    // variables
    address public constant REWARD_DELEGATOR = 0xE02F9154D6b12F36A726D3Cacf759da0D4cdA7FC;
    uint256 public expirationDate;

    function setUp() public virtual {
        vm.createSelectFork(REAL_RPC_URL, 1153570); // fork at: Nov 18 2024 09:32:03 AM (-07:00 UTC)
        
        // Upgrade Delegator beacon proxy
        vm.startPrank(MULTISIG);
        delegateFactory.updateDelegatorImplementation(address(new Delegator()));

        // Upgrade DelegateFactory
        delegateFactory.upgradeToAndCall(address(new DelegateFactory()), "");
        vm.stopPrank();
        
        _createLabels();
    }

    // -------
    // Utility
    // -------

    function _getDelegators() internal view returns (address[] memory) {
        return delegateFactory.getDelegatorsArray();
    }

    // function _getRewardTokens() internal view returns (uint256[] memory rewardTokens, uint256 size) {
    //     address[] memory delegators = _getDelegators();
    //     uint256 numDelegators = delegators.length;

    //     rewardTokens = new uint256[](delegators.length);

    //     for (uint256 i; i < numDelegators; ++i) {
    //         Delegator delegatorContract = Delegator(delegators[i]);
    //         if (delegatorContract.creator() == rewardDelegator) {
    //             rewardTokens[size] = delegatorContract.delegatedToken();
    //             ++size;
    //         }
    //     }
    // }

    // function _extractTokenFromDelegation(uint256 tokenId) internal {
    //     address[] memory delegator = _asSingletonArrayAddress(getDelegatorFromToken[tokenId]);
    //     vm.prank(REWARD_DELEGATOR);
    //     delegateFactory.revokeExpiredDelegators(delegator);
    // }

    /// @dev Instantiates labels for all global contracts.
    function _createLabels() internal {
        vm.label(address(rwaToken), "RWAToken");
        vm.label(address(rwaVotingEscrow), "RWAVotingEscrow");
        vm.label(address(revStream), "RevenueStreamETH");
        vm.label(JOE, "JOE");
        vm.label(REWARD_DELEGATOR, "REWARD_DELEGATOR");
    }
}