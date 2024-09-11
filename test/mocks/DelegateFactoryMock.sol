// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title DelegateFactoryMock
contract DelegateFactoryMock {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Maps contract address of Delegator to it's expiration date.
    mapping(address => uint256) public delegatorExpiration;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when deployDelegator is executed.
     * @param _delegator New address of delegator.
     */
    event DelegatorCreated(uint256 indexed tokenId, address indexed _delegator);


    // ----------------
    // External Methods
    // ----------------

    function deployDelegator(uint256 _tokenId, address _delegatee, uint256 _duration) external returns (address newDelegator) {
        require(_delegatee != address(0), "delegatee cannot be address(0)");
        require(_duration != 0, "duration must be greater than 0");

        newDelegator = _delegatee;
        delegatorExpiration[newDelegator] = block.timestamp + _duration;

        emit DelegatorCreated(_tokenId, _delegatee);
    }
}