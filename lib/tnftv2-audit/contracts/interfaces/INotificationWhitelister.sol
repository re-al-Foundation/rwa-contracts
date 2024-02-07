// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface INotificationWhitelister {
    function registerForNotification(uint256 tokenId) external;

    function unregisterForNotification(uint256 tokenId) external;

    function whitelistAddressAndReceiver(address receiver) external;

    function whitelistedReceiver(address) external returns (bool);
}
