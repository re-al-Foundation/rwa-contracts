// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { Votes } from "@openzeppelin/contracts/governance/utils/Votes.sol";

// local imports
import { DelegateFactory } from "./DelegateFactory.sol";

/**
 * @title Delegator
 * @author @chasebrownn
 * @notice This contract is used to delegate voting power of a single veRWA NFT to a specified account.
 *         This contract will be created by the DelegateFactory and will be assigned a delegatee.
 *         Upon creation, a veRWA NFT will be deposited in which the voting power is delegated to the delegatee.
 */
contract Delegator is Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Token Id of NFT that is delegated.
    uint256 public delegatedToken;
    /// @notice Contract reference of VotingEscrowRWA (veRWA) contract.
    IERC721Enumerable public votingEscrow;
    /// @notice Address being delegated voting power of `delegatedToken`
    address public delegatee;
    /// @notice EOA that was used to create the delegator.
    address public creator;
    /// @notice Address of the DelegateFactory contract.
    address public delegateFactory;
    /// @notice If true, delegatee can claim delegatedToken.
    bool public claimable;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when depositDelegatorToken is executed.
     * @param tokenId Token identifier of token being delegated.
     * @param delegatee Address of which the voting power of `tokenId` delegated to.
     */
    event TokenDelegated(uint256 indexed tokenId, address indexed delegatee);

    /**
     * @notice This event is emitted when withdrawDelegatedToken is executed.
     * @param tokenId Token identifier of token being withdrawn.
     * @param oldDelegatee Address of which the voting power of `tokenId` has removed delegated from.
     */
    event DelegationWithdrawn(uint256 indexed tokenId, address indexed oldDelegatee);

    /**
     * @notice This event is emitted when the delegatedToken is being claimed.
     * @param tokenId Token identifier of token being claimed.
     * @param claimedBy EOA that claimed token.
     */
    event TokenClaimed(uint256 indexed tokenId, address indexed claimedBy);

    /**
     * @notice This event is emitted when the value of claimable is updated.
     * @param claimable The new status stored in claimable.
     */
    event ClaimableStatusUpdated(bool claimable);

    
    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice This initializes the Delegator contract.
     * @param _veRWA VotingEscrowRWA contract address.
     * @param _creator EOA that was used to create this contract.
     * @param _delegatee Address the voting power was delegated to.
     */
    function initialize(
        address _veRWA,
        address _creator,
        address _delegatee
    ) external initializer {
        __Ownable_init(_creator);

        votingEscrow = IERC721Enumerable(_veRWA);
        creator = _creator;
        delegatee = _delegatee;
        delegateFactory = msg.sender;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice Allows the delegatee to claim the reward token from the Delegator.
     * @dev Can only be done if `claimable` is true.
     * If the token is claimed, this contract will call the DelegateFactory to remove itself
     * from existing Delegators.
     */
    function claimRewardToken() external nonReentrant {
        require(msg.sender == delegatee, "Delegator: Not authorized");
        require(claimable, "Delegator: Not claimable");

        emit TokenClaimed(delegatedToken, msg.sender);

        Votes(address(votingEscrow)).delegate(address(this));
        _pushToken(delegatedToken, msg.sender);

        DelegateFactory(delegateFactory).deleteDelegator();
    }

    /**
     * @notice This method is used to deposit a delegated veRWA NFT into this contract.
     * @dev There should only be 1 NFT deposited during the lifespan of this delegator.
     * @param tokenId Token identifier of veRWA token.
     */
    function depositDelegatorToken(uint256 tokenId) external {     
        require(msg.sender == delegateFactory, "Delegator: Not authorized");

        emit TokenDelegated(tokenId, delegatee);

        delegatedToken = tokenId;   

        _pullToken(tokenId);
        Votes(address(votingEscrow)).delegate(delegatee);
    }

    /**
     * @notice This method is used to transfer the `delegatedToken` back to the `creator`.
     */
    function withdrawDelegatedToken() external nonReentrant {
        require(msg.sender == delegateFactory || msg.sender == owner(), "Delegator: Not authorized");

        emit DelegationWithdrawn(delegatedToken, delegatee);

        Votes(address(votingEscrow)).delegate(address(this));
        _pushToken(delegatedToken, creator);
    }

    /**
     * @notice This method is used to allow the contract creator to update the claimable status of the delegatedToken.
     * @param isClaimable The new status being stored in claimable. Cannot be same as value already asigned.
     */
    function setClaimable(bool isClaimable) external {
        require(msg.sender == creator, "Delegator: Not authorized");
        require(claimable != isClaimable, "Delegator: Already set");

        emit ClaimableStatusUpdated(isClaimable);
        
        claimable = isClaimable;
    }


    // ----------------
    // Internal Methods
    // ----------------

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
}