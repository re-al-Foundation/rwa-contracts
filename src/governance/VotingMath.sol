// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title Voting Math Library
 * @author SeaZarrgh
 * @notice Provides functionality to calculate voting power based on the amount of tokens locked and the remaining
 * vesting duration. This model aligns voting power with vested interest, factoring in both the quantity of tokens and
 * the commitment length.
 * @dev The library calculates voting power as a function of the locked token amount and the proportion of the remaining
 * vesting duration to the maximum vesting duration. This calculation is intended to be used in governance systems where
 * longer commitments carry more weight.
 *
 * Constants:
 * - `MAX_VESTING_DURATION`: Represents the maximum duration for vesting, set to 2 years (104 weeks).
 */
library VotingMath {
    uint256 constant MAX_VESTING_DURATION = 36 * (30 days);

    /**
     * @dev Calculates the voting power based on the amount of tokens locked and the remaining vesting duration. The
     * voting power is proportional to the product of the locked amount and the remaining vesting duration, divided by
     * the maximum vesting duration.
     *
     * @param lockedAmount The amount of tokens that are locked.
     * @param remainingVestingDuration The remaining duration for which the tokens are locked.
     * @return The calculated voting power, scaled according to the remaining vesting duration and the locked amount.
     */
    function calculateVotingPower(uint256 lockedAmount, uint256 remainingVestingDuration)
        internal
        pure
        returns (uint256)
    {
        return lockedAmount * remainingVestingDuration / MAX_VESTING_DURATION;
    }
}
