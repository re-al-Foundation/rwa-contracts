// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface IRentNotificationDispatcher {
    function notify(
        address tnft,
        uint256 tokenId,
        uint256 unclaimedAmount,
        uint256 newDeposit,
        uint256 startTime,
        uint256 endTime
    ) external;
}
