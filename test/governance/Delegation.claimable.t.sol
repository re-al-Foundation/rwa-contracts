// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

// local helper imports
import "./utils/Delegation.claimable.setUp.sol";
import "../../src/interfaces/CommonErrors.sol";

/**
 * @title DelegationClaimableTest
 * @author @chasebrownn
 * @notice This test file contains unit tests for Delegator claimability.
 * @dev Claimability is an added feature to facilitate the claiming of season 1 points rewards.
 */
contract DelegationClaimableTest is Test, DelegationClaimableTestUtility {

    function setUp() public override {
        super.setUp();
    }


    // -------
    // Utility
    // -------

    /// @dev Returns first token in the token set.
    function _getToken() internal view returns (uint256) {
        return sampleDataSet[0];
    }

    /// @dev Returns the delegator for the first token in the token set.
    function _getDelegator() internal view returns (Delegator) {
        return Delegator(getDelegatorFromToken[_getToken()]);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev This test verifies the proper state changes when Delegator::setClaimable is executed.
    function test_delegator_setClaimable() public {
        // ~ Config ~

        Delegator delegator = _getDelegator();

        // ~ Pre-state check ~

        assertEq(delegator.claimable(), false);

        // ~ Call setClaimable ~

        vm.prank(REWARD_DELEGATOR);
        delegator.setClaimable(true);

        // ~ Post-state check ~

        assertEq(delegator.claimable(), true);
    }

    /// @dev This test verifies if Delegator::setClaimable is executed by an unauthorized msg.sender,
    /// the contract emits the expected revert statement.
    function test_delegator_setClaimable_notAuthorized() public {
        Delegator delegator = _getDelegator();
        vm.expectRevert("Delegator: Not authorized");
        delegator.setClaimable(true);
    }
    
    /// @dev This test verifies if Delegator::setClaimable is executed for an existing value,
    /// the contract emits the expected revert statement.
    function test_delegator_setClaimable_alreadySet() public {
        Delegator delegator = _getDelegator();
        vm.prank(REWARD_DELEGATOR);
        vm.expectRevert("Delegator: Already set");
        delegator.setClaimable(false);
    }

    /// @dev This test verifies the proper state changes when Delegator::claimRewardToken is executed.
    function test_delegator_claimRewardToken() public {
        // ~ Config ~

        uint256 tokenId = _getToken();
        Delegator delegator = _getDelegator();
        address delegatee = delegator.delegatee();

        vm.label(address(delegator), "DELEGATOR");
        vm.label(delegatee, "DELEGATEE");

        vm.prank(REWARD_DELEGATOR);
        delegator.setClaimable(true);

        // ~ Pre-state check ~

        uint256 delegateeVoting = rwaVotingEscrow.getVotes(delegatee);
        uint256 indexInArray = delegateFactory.indexInDelegators(address(delegator));
        uint256 amountDelegators = delegateFactory.getDelegatorsArray().length;
        address lastDelegator = delegateFactory.delegators(amountDelegators - 1);

        // check owner of tokenId
        assertEq(rwaVotingEscrow.ownerOf(tokenId), address(delegator));
        // check Delegator status on DelegateFactory
        assertEq(delegateFactory.isDelegator(address(delegator)), true);
        assertEq(delegateFactory.delegators(indexInArray), address(delegator));

        // ~ Call setClaimable ~

        vm.prank(delegatee);
        delegator.claimRewardToken();

        // ~ Post-state check ~

        // check owner of tokenId
        assertEq(rwaVotingEscrow.ownerOf(tokenId), delegatee);
        // check Delegator was removed from DelegateFactory
        assertEq(delegateFactory.isDelegator(address(delegator)), false);
        assertEq(delegateFactory.delegators(indexInArray), lastDelegator);
        assertEq(delegateFactory.indexInDelegators(address(delegator)), 0);
        assertEq(delegateFactory.getDelegatorsArray().length, amountDelegators - 1);
        // check voting power of delegatee does not change
        assertEq(rwaVotingEscrow.getVotes(delegatee), delegateeVoting);
    }

    /// @dev This test verifies the proper state changes when Delegator::claimRewardToken is executed
    /// for a data set of delegators.
    function test_delegator_claimRewardToken_allTokens() public {
        uint256[] memory dataSet = getSampleDataSet();
        for (uint256 i; i < dataSet.length; ++i) {
            // ~ Config ~

            uint256 tokenId = dataSet[i];
            Delegator delegator = Delegator(getDelegatorFromToken[tokenId]);
            address delegatee = delegator.delegatee();

            vm.label(address(delegator), "DELEGATOR");
            vm.label(delegatee, "DELEGATEE");

            vm.prank(REWARD_DELEGATOR);
            delegator.setClaimable(true);

            // ~ Pre-state check ~

            uint256 delegateeVoting = rwaVotingEscrow.getVotes(delegatee);
            uint256 indexInArray = delegateFactory.indexInDelegators(address(delegator));
            uint256 amountDelegators = delegateFactory.getDelegatorsArray().length;
            address lastDelegator = delegateFactory.delegators(amountDelegators - 1);

            // check owner of tokenId
            assertEq(rwaVotingEscrow.ownerOf(tokenId), address(delegator));
            // check Delegator status on DelegateFactory
            assertEq(delegateFactory.isDelegator(address(delegator)), true);
            assertEq(delegateFactory.delegators(indexInArray), address(delegator));

            // ~ Call setClaimable ~

            vm.prank(delegatee);
            delegator.claimRewardToken();

            // ~ Post-state check ~

            // check owner of tokenId
            assertEq(rwaVotingEscrow.ownerOf(tokenId), delegatee);
            // check Delegator was removed from DelegateFactory
            assertEq(delegateFactory.isDelegator(address(delegator)), false);
            assertEq(delegateFactory.delegators(indexInArray), lastDelegator);
            assertEq(delegateFactory.indexInDelegators(address(delegator)), 0);
            assertEq(delegateFactory.getDelegatorsArray().length, amountDelegators - 1);
            // check voting power of delegatee does not change
            assertEq(rwaVotingEscrow.getVotes(delegatee), delegateeVoting);
        }
    }

    /// @dev Verifies when Delegator::claimRewardToken when msg.sender is not a delegatee,
    /// we get the expected revert statement.
    function test_delegator_claimRewardToken_notAuthorized() public {
        // ~ Config ~

        Delegator delegator = _getDelegator();

        vm.prank(REWARD_DELEGATOR);
        delegator.setClaimable(true);

        vm.expectRevert("Delegator: Not authorized");
        delegator.claimRewardToken();
    }

    /// @dev Verifies when Delegator::claimRewardToken while claimable is false,
    /// we get the expected revert statement.
    function test_delegator_claimRewardToken_notClaimable() public {
        // ~ Config ~

        Delegator delegator = _getDelegator();
        address delegatee = delegator.delegatee();

        vm.prank(delegatee);
        vm.expectRevert("Delegator: Not claimable");
        delegator.claimRewardToken();
    }

    /// @dev Verifies proper state changes when DelegateFactory::updateDelegatorExpiration is executed.
    function test_delegator_delegateFactory_updateDelegatorExpiration() public {
        // ~ Config ~

        Delegator delegator = _getDelegator();
        uint256 expiration = delegateFactory.delegatorExpiration(address(delegator));
        uint256 newExpiration = expiration + 30 * 1 days;

        // ~ Pre-state check ~

        assertNotEq(delegateFactory.delegatorExpiration(address(delegator)), newExpiration);

        // ~ updateDelegatorExpiration ~

        vm.prank(REWARD_DELEGATOR);
        delegateFactory.updateDelegatorExpiration(address(delegator), newExpiration);

        // ~ Post-state check ~

        assertEq(delegateFactory.delegatorExpiration(address(delegator)), newExpiration);
    }
}