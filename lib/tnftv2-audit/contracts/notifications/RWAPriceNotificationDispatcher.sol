// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../abstract/NotificationWhitelister.sol";
import "../interfaces/ITangibleNFT.sol";
import "../interfaces/ITangiblePriceManager.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IRWAPriceNotificationDispatcher.sol";
import "./IRWAPriceNotificationReceiver.sol";

/**
 * @title RWAPriceNotificationDispatcher
 * @author Veljko Mihailovic
 * @notice This contract is used to push notification on rwa price change.
 */
contract RWAPriceNotificationDispatcher is
    IRWAPriceNotificationDispatcher,
    NotificationWhitelister
{
    // ~ Events ~
    event Notified(
        address indexed receiver,
        uint256 indexed fingerprint,
        uint16 indexed currency,
        uint256 oldNativePrice,
        uint256 newNativePrice
    );

    // ~ Modifiers ~
    modifier onlyTnftOracle() {
        require(
            msg.sender == address(IFactory(factory()).priceManager().oracleForCategory(tnft())),
            "Not ok oracle"
        );
        _;
    }

    // ~ Initialize ~
    /**
     *
     * @param _factory Factory contract address
     * @param _tnft Tnft address for which notifications are registered
     */
    function initialize(address _factory, address _tnft) external initializer {
        __NotificationWhitelister_init(_factory, _tnft);
    }

    // ~ External Functions ~
    /**
     *
     * @param fingerprint Item ofr which the price has changed
     * @param oldNativePrice old price of the item, native currency
     * @param newNativePrice old price of the item, native currency
     * @param currency Currency in which the price is expressed
     */
    function notify(
        uint256 fingerprint,
        uint256 oldNativePrice,
        uint256 newNativePrice,
        uint16 currency
    ) external onlyTnftOracle {
        ITangibleNFT _tnft = tnft();
        uint256 tokenId = _tnft.fingerprintTokens(fingerprint, 0);
        if (tokenId != 0) {
            // if in if to save gas
            address receiver = registeredForNotification(address(_tnft), tokenId);
            if (receiver != address(0)) {
                IRWAPriceNotificationReceiver(receiver).notify(
                    address(_tnft),
                    tokenId,
                    fingerprint,
                    oldNativePrice,
                    newNativePrice,
                    currency
                );
                emit Notified(receiver, fingerprint, currency, oldNativePrice, newNativePrice);
            }
        }
    }
}
