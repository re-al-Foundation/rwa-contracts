// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { Votes } from "@openzeppelin/contracts/governance/utils/Votes.sol";

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
    IERC721Enumerable public veRWA;
    /// @notice Address being delegated voting power of `delegatedToken`
    address public delegatee;
    /// @notice EOA that was used to create the delegator.
    address public creator;
    /// @notice Address of the DelegateFactory contract.
    address public delegateFactory;

    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when depositDelegatorToken is executed.
     * @param _tokenId Token identifier of token being delegated.
     * @param _delegatee Address of which the voting power of `tokenId` delegated to.
     */
    event TokenDelegated(uint256 indexed _tokenId, address indexed _delegatee);

    /**
     * @notice This event is emitted when withdrawDelegatedToken is executed.
     * @param _tokenId Token identifier of token being withdrawn.
     * @param _oldDelegatee Address of which the voting power of `tokenId` has removed delegated from.
     */
    event DelegationWithdrawn(uint256 indexed _tokenId, address indexed _oldDelegatee);

    
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

        veRWA = IERC721Enumerable(_veRWA);
        creator = _creator;
        delegatee = _delegatee;
        delegateFactory = msg.sender;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method is used to deposit a delegated veRWA NFT into this contract.
     * @dev There should only be 1 NFT deposited during the lifespan of this delegator.
     * @param _tokenId Token identifier of veRWA token.
     */
    function depositDelegatorToken(uint256 _tokenId) external {     
        require(msg.sender == delegateFactory, "Delegator: Not authorized");

        delegatedToken = _tokenId;   

        veRWA.transferFrom(msg.sender, address(this), _tokenId);
        Votes(address(veRWA)).delegate(delegatee);

        emit TokenDelegated(_tokenId, delegatee);
    }

    /**
     * @notice This method is used to transfer the `delegatedToken` back to the `creator`.
     */
    function withdrawDelegatedToken() external nonReentrant {
        require(msg.sender == delegateFactory || msg.sender == owner(), "Delegator: Not authorized");

        Votes(address(veRWA)).delegate(address(this));
        veRWA.transferFrom(address(this), creator, delegatedToken);

        emit DelegationWithdrawn(delegatedToken, delegatee);
    }
}