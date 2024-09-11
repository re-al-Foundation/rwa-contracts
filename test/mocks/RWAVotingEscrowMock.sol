// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { VotingMath } from "../../src/governance/VotingMath.sol";

/// @title RWAVotingEscrowMock 
contract RWAVotingEscrowMock {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Stores the minimum vesting duration for a lock period.
    uint256 public constant MIN_VESTING_DURATION = 1 * (30 days);
    /// @notice Stores the maximum vesting duration for a lock period.
    uint256 public constant MAX_VESTING_DURATION = VotingMath.MAX_VESTING_DURATION;

    /// @notice Is used to create next tokenId for each NFT minted.
    uint256 public tokenId;


    // ------
    // Events
    // ------

    event LockCreated(uint256 indexed tokenId, uint208 lockedAmount, uint256 duration);


    // ------
    // Errors
    // ------

    /**
     * @notice This error is emitted when an account attempts to crate a lock with 0 locked balance.
     */
    error ZeroLockBalance();

    /**
     * @notice This error is emitted when the lock duration is invalid.
     * @param duration The desired duration of lock.
     * @param min The minimum allowed duration.
     * @param max The maximum allowed duration.
     */
    error InvalidVestingDuration(uint256 duration, uint256 min, uint256 max);
    

    // ----------------
    // External Methods
    // ----------------

    function mint(address _receiver, uint208 _lockedBalance, uint256 _duration) external returns (uint256 _tokenId) {
        // if _lockedBalance is 0, revert
        if (_lockedBalance == 0) revert ZeroLockBalance();
        require(_receiver != address(0), "address(0) Exception");
        // if _duration is not within range, revert
        if (_duration < MIN_VESTING_DURATION || _duration > MAX_VESTING_DURATION) {
            revert InvalidVestingDuration(_duration, MIN_VESTING_DURATION, MAX_VESTING_DURATION);
        }

        _tokenId = ++tokenId;
        emit LockCreated(_tokenId, _lockedBalance, _duration);
    }

    function getTokenId() external view returns (uint256) {
        return tokenId;
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @notice Returns the current block.timestamp.
     */
    function clock() public view returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure returns (string memory) {
        return "mode=timestamp";
    }
}
