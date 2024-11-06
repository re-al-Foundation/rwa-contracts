// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// oz imports
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// local imports
import { CommonValidations } from "../libraries/CommonValidations.sol";

/**
 * @title RewardEscrow
 * @author @chasebrownn
 * @notice This contract allows veRWA NFTs to be placed into escrow to be claimed by a designated beneficiary. If the beneficiary
 * does not claim the NFT within the specified timeframe, the token is taken into protocol custody.
 */
contract RewardEscrow is UUPSUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using CommonValidations for *;
    using EnumerableSet for EnumerableSet.UintSet;

    // ---------------
    // State Variables
    // ---------------

    /// @dev Used to track escrow elements for each token deposited.
    struct TokenData {
        /// @dev Address which is given the rights to claim the token in escrow.
        address beneficiary;
        /// @dev Timestamp when the token in escrow becomes no longer claimable by beneficiary.
        uint256 expiration;
        /// @dev Address of account that deposited the token in escrow.
        address depositedBy;
    }

    /// @dev Contract reference for RWAVotingEscrow contract.
    IERC721Enumerable public constant votingEscrow = IERC721Enumerable(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);
    /// @dev Stores the set of tokenIds stored in this contract.
    EnumerableSet.UintSet private tokenSet;
    /// @dev Maps tokenId to escrow data.
    mapping(uint256 tokenId => TokenData data) public escrowData;


    // ---------------
    // Events & Errors
    // ---------------

    event TokenClaimed(uint256 indexed tokenId, address indexed claimedBy);
    event TokenDeposited(uint256 indexed tokenId, uint256 expiration, address indexed beneficiary, address depositedBy);

    error InvalidToken(uint256 tokenId);
    error InvalidBeneficiary(address beneficiary, address thief);
    error ClaimingExpiredForToken(uint256 tokenId, uint256 expiration);


    // -----------
    // Initializer
    // -----------

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice This initializes the RewardEscrow contract.
     * @param admin Admin address.
     */
    function initialize(
        address admin
    ) external initializer {
        admin.requireNonZeroAddress();
        __Ownable_init(admin);
    }


    // --------
    // External
    // --------

    // TODO: What to do with expired tokens?? A: claim by admin

    function claimRewardToken(uint256 tokenId) external nonReentrant { // TODO: Test gas with msg.sender vs beneficiary.
        if (!isWithinTokenSet(tokenId)) revert InvalidToken(tokenId);
        address beneficiary = getBeneficiary(tokenId);
        if (beneficiary != msg.sender) revert InvalidBeneficiary(beneficiary, msg.sender);
        if (isExpired(tokenId)) revert ClaimingExpiredForToken(tokenId, escrowData[tokenId].expiration);

        emit TokenClaimed(tokenId, beneficiary);

        _pushToken(tokenId, beneficiary);
        // TODO: Revoke delegation

        tokenSet.remove(tokenId);

        delete escrowData[tokenId];
    }

    function depositToken(uint256 tokenId, address beneficiary, uint256 expiration) external nonReentrant {
        beneficiary.requireNonZeroAddress();
        tokenId.requireDifferentUint256(0);
        // TODO: Require msg.sender is owner of token - might not be needed - transferFrom check?

        emit TokenDeposited(tokenId, expiration, beneficiary, msg.sender);

        _pullToken(tokenId);
        // TODO: Delegate tokenId voting power to beneficiary

        tokenSet.add(tokenId);

        escrowData[tokenId] = TokenData({
            beneficiary: beneficiary,
            expiration: expiration,
            depositedBy: msg.sender
        });
    }

    // TODO
    function withdrawExpiredToken(uint256 tokenId) external {
        // must be expired
        // msg.sender must be original depositor of token
        // transfer token to msg.sender
        // revoke delegation
        // delete data
    }

    /**
     * @notice Returns the length of `tokenSet`. Which is equivalent to the amount of tokens currently placed into escrow.
     */
    function tokenSetLength() external view returns (uint256) {
        return tokenSet.length();
    }

    /**
     * @notice Returns the tokenId stored at the provided `index`.
     */
    function getTokenAtIndex(uint256 index) external view returns (uint256) {
        return tokenSet.at(index);
    }

    /**
     * @notice Returns the full array stored within `tokenSet`.
     */
    function getTokenSet() external view returns (uint256[] memory) {
        return tokenSet.values();
    }

    /**
     * @notice Returns all escrow data for a `tokenId`.
     * @dev Returned as type TokenData.
     */
    function getEscrowData(uint256 tokenId) external view returns (TokenData memory) {
        return escrowData[tokenId];
    }


    // ------
    // Public
    // ------

    /**
     * @notice If the provided `tokenId` is within the tokenSet (aka "in-escrow") this method will return true.
     * Otherwise will return false.
     */
    function isWithinTokenSet(uint256 tokenId) public view returns (bool) {
        return tokenSet.contains(tokenId);
    }

    /**
     * @notice Returns the beneficiary of the `tokenId` in escrow.
     * @dev Will return address(0) if the token is invalid.
     */
    function getBeneficiary(uint256 tokenId) public view returns (address) {
        return escrowData[tokenId].beneficiary;
    }

    /**
     * @notice If the `tokenId` is in escrow and not expired will return false, otherwise true.
     */
    function isExpired(uint256 tokenId) public view returns (bool) {
        return block.timestamp > escrowData[tokenId].expiration;
    }


    // --------
    // Internal
    // --------

    /**
     * @notice Internal method for transferring a `tokenId` into the custody of this contract.
     */
    function _pullToken(uint256 tokenId) internal {
        votingEscrow.transferFrom(msg.sender, address(this), tokenId);
    }

    /**
     * @notice Internal method for transferring a `tokenId` from this contract to a `to` address.
     */
    function _pushToken(uint256 tokenId, address to) internal {
        votingEscrow.transferFrom(address(this), to, tokenId);
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the owner role to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}