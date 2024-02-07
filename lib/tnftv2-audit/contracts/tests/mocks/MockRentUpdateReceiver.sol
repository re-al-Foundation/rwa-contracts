// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../../notifications/IRentNotificationReceiver.sol";
import "../../interfaces/INotificationWhitelister.sol";

contract MockRentUpdateReceiver is IRentNotificationReceiver {
    event Received(address tnft, uint256 tokenId, uint256 unclaimedAmount, uint256 newDeposit);

    address public immutable tnft;
    address public immutable rentDispatcher;
    uint256 public immutable tokenId;
    uint256 public unclaimedAmount;
    uint256 public newDeposit;
    uint256 public startTime;
    uint256 public endTime;

    constructor(address _tnft, uint256 _tokenId, address _rentDispatcher) {
        tnft = _tnft;
        tokenId = _tokenId;
        rentDispatcher = _rentDispatcher;
    }

    function registerForNotification() external {
        INotificationWhitelister(rentDispatcher).registerForNotification(tokenId);
    }

    function unregisterForNotification() external {
        INotificationWhitelister(rentDispatcher).unregisterForNotification(tokenId);
    }

    function notify(
        address _tnft,
        uint256 _tokenId,
        uint256 _unclaimedAmount,
        uint256 _newDeposit,
        uint256 _startTime,
        uint256 _endTime
    ) external override {
        require(_tnft == tnft, "Wrong TNFT");
        require(_tokenId == tokenId, "Wrong TokenID");
        unclaimedAmount = _unclaimedAmount;
        newDeposit = _newDeposit;
        startTime = _startTime;
        endTime = _endTime;
        emit Received(tnft, tokenId, unclaimedAmount, newDeposit);
    }
}
