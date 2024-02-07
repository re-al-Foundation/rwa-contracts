// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../../notifications/IRWAPriceNotificationReceiver.sol";
import "../../interfaces/INotificationWhitelister.sol";

contract MockRWAPriceUpdateReceiver is IRWAPriceNotificationReceiver {
    event Received(
        uint256 tokenId,
        uint256 fingerprint,
        uint256 oldNativePrice,
        uint256 newNativePrice,
        uint16 currency
    );

    address public immutable tnft;
    address public immutable priceDispatcher;
    uint256 public immutable tokenId;
    uint256 public fingerprint;
    uint256 public oldNativePrice;
    uint256 public newNativePrice;
    uint16 public currency;

    constructor(address _tnft, uint256 _tokenId, address _priceDispatcher) {
        tnft = _tnft;
        tokenId = _tokenId;
        priceDispatcher = _priceDispatcher;
    }

    function registerForNotification() external {
        INotificationWhitelister(priceDispatcher).registerForNotification(tokenId);
    }

    function unregisterForNotification() external {
        INotificationWhitelister(priceDispatcher).unregisterForNotification(tokenId);
    }

    function notify(
        address _tnft,
        uint256 _tokenId,
        uint256 _fingerprint,
        uint256 _oldNativePrice,
        uint256 _newNativePrice,
        uint16 _currency
    ) external override {
        require(tnft == _tnft, "Wrong TNFT");
        require(tokenId == _tokenId, "Wrong TokenID");
        oldNativePrice = _oldNativePrice;
        newNativePrice = _newNativePrice;
        currency = _currency;
        emit Received(_tokenId, _fingerprint, oldNativePrice, newNativePrice, currency);
    }
}
