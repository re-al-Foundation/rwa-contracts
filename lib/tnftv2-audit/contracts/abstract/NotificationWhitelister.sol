// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./FactoryModifiers.sol";
import "../interfaces/ITangibleNFT.sol";
import "../interfaces/INotificationWhitelister.sol";

abstract contract NotificationWhitelister is FactoryModifiers, INotificationWhitelister {
    /// @custom:storage-location erc7201:tangible.storage.NotificationWhitelister
    struct NotificationWhitelisterStorage {
        /// @notice mapping of tnft tokenIds to addresses that are registered for notification
        mapping(address => mapping(uint256 => address)) registeredForNotification;
        /// @notice mapping of whitelisted addresses that can register for notification
        mapping(address => bool) whitelistedReceiver;
        /// @dev mapping of addresses that can whitelist other addresses
        mapping(address => bool) approvedWhitelisters;
        /// @notice  tnft for which tokens are registered for notification
        ITangibleNFT tnft;
    }

    // keccak256(abi.encode(uint256(keccak256("tangible.storage.NotificationWhitelister")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NotificationWhitelisterStorageLocation =
        0x212c2e666f9b1835ae76799b54e7464b437586737923bee1d2bd33a2e4bfcd00;

    /**
     * @notice This internal method is used to get the NotificationWhitelisterStorage struct.
     */
    function _getNotificationWhitelisterStorage()
        private
        pure
        returns (NotificationWhitelisterStorage storage $)
    {
        assembly {
            $.slot := NotificationWhitelisterStorageLocation
        }
    }

    modifier onlyApprovedWhitelister() {
        _checkApprover();
        _;
    }

    function __NotificationWhitelister_init(
        address _factory,
        address _tnft
    ) internal onlyInitializing {
        __FactoryModifiers_init(_factory);
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        $.tnft = ITangibleNFT(_tnft);
    }

    // ~ View function and setters, so that contract can be upgradeable

    function tnft() public view virtual returns (ITangibleNFT) {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        return $.tnft;
    }

    function registeredForNotification(
        address _tnft,
        uint256 _tokenId
    ) public view virtual returns (address) {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        return $.registeredForNotification[_tnft][_tokenId];
    }

    function whitelistedReceiver(address _receiver) public view virtual returns (bool) {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        return $.whitelistedReceiver[_receiver];
    }

    function approvedWhitelisters(address _whitelister) public view virtual returns (bool) {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        return $.approvedWhitelisters[_whitelister];
    }

    // ~ Functions ~

    /**
     * @notice adds an address that can whitelist others, only callable by the category owner
     *
     * @param _whitelister Address that can whitelist other addresses besides category owner
     */
    function addWhitelister(address _whitelister) external onlyCategoryOwner(ITangibleNFT(tnft())) {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        $.approvedWhitelisters[_whitelister] = true;
    }

    /**
     * @notice removes an address that can whitelist others, only callable by the category owner
     *
     * @param _whitelister Address that can whitelist other addresses besides category owner
     */
    function removeWhitelister(
        address _whitelister
    ) external onlyCategoryOwner(ITangibleNFT(tnft())) {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        $.approvedWhitelisters[_whitelister] = false;
    }

    /**
     *
     * @param receiver Address that will be whitelisted
     */
    function whitelistAddressAndReceiver(address receiver) external onlyApprovedWhitelister {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        require(!$.whitelistedReceiver[receiver], "Already whitelisted");
        $.whitelistedReceiver[receiver] = true;
    }

    /**
     *
     * @param receiver Address that will be blacklisted
     */
    function blacklistAddress(address receiver) external onlyApprovedWhitelister {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        require($.whitelistedReceiver[receiver], "Not whitelisted");
        $.whitelistedReceiver[receiver] = false;
    }

    /**
     * @notice Registers or unregisters an address for notification, only callable by the category owner
     *
     * @param tokenId TokenId for which the address will be registered for notification
     * @param receiver Address that will be registered for notification
     * @param register Boolean that determines if the address will be registered or unregistered
     */
    function registerUnregisterForNotification(
        uint256 tokenId,
        address receiver,
        bool register
    ) external onlyCategoryOwner(ITangibleNFT(tnft())) {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        if (register) {
            $.registeredForNotification[address($.tnft)][tokenId] = receiver;
        } else {
            delete $.registeredForNotification[address($.tnft)][tokenId];
        }
    }

    /**
     *
     * @param tokenId TokenId for which the address will be registered for notification
     */
    function registerForNotification(uint256 tokenId) external {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        require($.whitelistedReceiver[msg.sender], "Not whitelisted");
        require($.tnft.ownerOf(tokenId) == msg.sender, "Not owner");
        $.registeredForNotification[address($.tnft)][tokenId] = msg.sender;
    }

    /**
     *
     * @param tokenId TokenId for which the address will be unregistered for notification
     */
    function unregisterForNotification(uint256 tokenId) external {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        require($.whitelistedReceiver[msg.sender], "Not whitelisted");
        require($.tnft.ownerOf(tokenId) == msg.sender, "Not owner");
        delete $.registeredForNotification[address($.tnft)][tokenId];
    }

    /**
     * @notice Checks if the address is approved whitelister
     *
     */
    function _checkApprover() internal view {
        NotificationWhitelisterStorage storage $ = _getNotificationWhitelisterStorage();
        require(
            IFactory(factory()).categoryOwner($.tnft) == msg.sender ||
                $.approvedWhitelisters[msg.sender],
            "NAPPW"
        );
    }
}
