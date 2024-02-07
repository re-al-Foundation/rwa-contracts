// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../abstract/NotificationWhitelister.sol";
import "../interfaces/ITangibleNFT.sol";
import "../interfaces/ITangiblePriceManager.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IRentNotificationDispatcher.sol";
import "./IRentNotificationReceiver.sol";

/**
 * @title RentNotificationDispatcher
 * @author Veljko Mihailovic
 * @notice This contract is used to push notification on rent deposits.
 */
contract RentNotificationDispatcher is IRentNotificationDispatcher, NotificationWhitelister {
    address public rentManager;

    // ~ Events ~
    event Notified(
        address indexed receiver,
        uint256 indexed tokenID,
        uint256 unclaimedAmount,
        uint256 newDeposit
    );

    // ~ Modifiers ~
    modifier onlyTnftRentManager() {
        require(msg.sender == rentManager, "Not ok oracle");
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
        rentManager = address(IFactory(_factory).rentManager(ITangibleNFT(_tnft)));
    }

    // ~ External Functions ~
    /**
     *
     * @param _tnft Tnft address for which notifications are registered
     * @param tokenId tokenID for which the price has changed
     * @param unclaimedAmount Amount of unclaimed rent
     * @param newDeposit New deposit of the rent
     * @param startTime When the rent vesting started
     * @param endTime When the rent vesting ends
     */
    function notify(
        address _tnft,
        uint256 tokenId,
        uint256 unclaimedAmount,
        uint256 newDeposit,
        uint256 startTime,
        uint256 endTime
    ) external onlyTnftRentManager {
        // if in if to save gas in case nothing registered
        if (_tnft == address(tnft())) {
            address receiver = registeredForNotification(address(tnft()), tokenId);
            if (receiver != address(0)) {
                IRentNotificationReceiver(receiver).notify(
                    address(tnft()),
                    tokenId,
                    unclaimedAmount,
                    newDeposit,
                    startTime,
                    endTime
                );
                emit Notified(receiver, tokenId, unclaimedAmount, newDeposit);
            }
        }
    }
}
