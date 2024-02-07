// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface IRWAPriceNotificationDispatcher {
    function notify(
        uint256 fingerprint,
        uint256 oldNativePrice,
        uint256 newNativePrice,
        uint16 currency
    ) external;
}
