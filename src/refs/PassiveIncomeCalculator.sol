// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "./Globals.sol";

abstract contract IPassiveIncomeCalculator {
    function claimableIncome(
        uint256 startTime,
        uint256 endTime,
        uint256 currentTime,
        uint256 startBalance,
        uint256 endBalance,
        uint256 claimed
    ) external view virtual returns (uint256, uint256);

    function determineMultiplier(
        uint256 start,
        uint256 end,
        uint256 timestamp,
        uint256 lockDurationInMonths
    ) public view virtual returns (uint256);

    function determineMultipliers(
        uint256 start,
        uint256 end,
        uint256 timestamp,
        uint256[] calldata lockDurationsInMonths
    ) external view virtual returns (uint256[] memory);
}

contract PassiveIncomeCalculator is IPassiveIncomeCalculator {
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _totalPayout(
        uint256 startTime,
        uint256 endTime,
        uint256 currentTime,
        uint256 startBalance,
        uint256 multiplier
    ) private pure returns (uint256) {
        if (currentTime == endTime) {
            return (startBalance * multiplier) / 1e18;
        }
        return
            (startBalance * multiplier * (currentTime - startTime)**2) /
            (1e18 * (endTime - startTime)**2);
    }

    function claimableIncome(
        uint256 startTime,
        uint256 endTime,
        uint256 currentTime,
        uint256 startBalance,
        uint256 multiplier,
        uint256 claimed
    ) external pure override returns (uint256 freeClaim, uint256 maxClaim) {
        if (currentTime > endTime) {
            currentTime = endTime;
        }
        maxClaim = _totalPayout(
            startTime,
            endTime,
            currentTime,
            startBalance,
            multiplier - 1e18
        );
        if (claimed > 0) {
            if (claimed >= maxClaim) {
                maxClaim = 0;
            } else {
                maxClaim -= claimed;
            }
        }
        if (currentTime == endTime) {
            freeClaim = maxClaim;
        } else {
            freeClaim =
                (((((currentTime - startTime) * 1e9) / (endTime - startTime)) **
                    2) * maxClaim) /
                1e18;
        }
    }

    function determineMultiplier(
        uint256 start,
        uint256 end,
        uint256 timestamp,
        uint256 lockDurationInMonths
    ) public pure override returns (uint256) {
        uint256 base;
        uint256 adjustedEnd = end - MIN_LOCK_DURATION * 30 * 86400;
        if (timestamp >= adjustedEnd) {
            return 1e18;
        }
        uint256 eod5 = start + 86400 * 5;
        if (timestamp >= eod5) {
            // after day 5
            base = 5e18;
            if (timestamp < adjustedEnd) {
                base +=
                    (10e18 * (adjustedEnd - timestamp)) /
                    (adjustedEnd - eod5);
            }
        } else if (timestamp >= start + 86400 * 4) {
            // after day 4
            base = 15e18;
        } else if (timestamp >= start + 86400 * 3) {
            // after day 3
            base = 175e17;
        } else if (timestamp >= start + 86400 * 2) {
            // after day 2
            base = 20e18;
        } else if (timestamp >= start + 86400) {
            // after day 1
            base = 225e17;
        } else {
            // day 1
            assert(timestamp >= start);
            base = 25e18;
        }
        if (lockDurationInMonths < MAX_LOCK_DURATION) {
            base =
                (base *
                    (((lockDurationInMonths * 1e9) / MAX_LOCK_DURATION)**2)) /
                1e18;
            if (base < 1e18) {
                base = 1e18;
            }
        }
        return base;
    }

    function determineMultipliers(
        uint256 start,
        uint256 end,
        uint256 timestamp,
        uint256[] calldata lockDurationsInMonths
    ) external pure override returns (uint256[] memory multipliers) {
        uint256 len = lockDurationsInMonths.length;
        multipliers = new uint256[](len);
        while (len > 0) {
            len--;
            multipliers[len] = determineMultiplier(
                start,
                end,
                timestamp,
                lockDurationsInMonths[len]
            );
        }
    }
}