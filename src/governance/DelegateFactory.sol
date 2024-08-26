// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

// local imports
import { Delegator } from "./Delegator.sol";
import { IDelegator } from "../interfaces/IDelegator.sol";

/**
 * @title DelegateFactory
 * @author @chasebrownn
 * @notice This contract acts as a factory for creating Delegator contracts.
 *         A permissioned admin can create delegator contracts to deposit Voting Escrow tokens to delegate voting power
 *         to a delegatee.
 */
contract DelegateFactory is UUPSUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    /// @notice If true, key address can deploy delegators, delegating voting power.
    mapping(address => bool) public canDelegate;
    /// @notice Mapping that stores whether a specified address is a delegator.
    mapping(address => bool) public isDelegator;
    /// @notice Maps contract address of Delegator to it's expiration date.
    mapping(address => uint256) public delegatorExpiration;
    /// @notice Contract reference for RWAVotingEscrow contract.
    IERC721Enumerable public veRWA;
    /// @notice Array of all delegators deployed.
    address[] public delegators;
    /// @notice UpgradeableBeacon contract instance. Deployed by this contract upon initialization.
    UpgradeableBeacon public beacon;
    /// @notice Stores the maximum amount of delegators we can have deployed at one time.
    uint256 public delegatorLimit;
    /// @notice Stores a index value for each delegator in the `delegators` array.
    mapping(address delegator => uint256 index) public indexInDelegators;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when deployDelegator is executed.
     * @param _delegator New address of delegator.
     */
    event DelegatorCreated(address indexed _delegator);

    /**
     * @notice This event is emitted when revokeAllExpiredDelegators is executed for each expired Delegator.
     * @param _delegator Address of revoked delegator.
     */
    event DelegatorDeleted(address indexed _delegator);

    /**
     * @notice This event is emitted when a new `canDelegate` is set.
     * @param newDelegatorRole New value stored in `canDelegate`.
     * @param canDelegate If true, `newDelegatorRole` address can delegate via deployDelegator.
     */
    event DelegatorRoleSet(address indexed newDelegatorRole, bool canDelegate);

    
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
     * @notice This initializes the DelegateFactory contract.
     * @param _veRWA VotingEscrowRWA contract address.
     * @param _initDelegatorBase Implementation address for Delegate beacon proxies.
     * @param _admin Admin address.
     */
    function initialize(
        address _veRWA,
        address _initDelegatorBase,
        address _admin
    ) external initializer {
        require(_admin != address(0));
        require(_initDelegatorBase != address(0));
        require(_veRWA != address(0));

        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        veRWA = IERC721Enumerable(_veRWA);
        beacon = new UpgradeableBeacon(_initDelegatorBase, address(this));
        delegatorLimit = 100;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows a permissioned address to create a delegator contract.
     * @param _tokenId Token identifier for NFT being delegated.
     * @param _delegatee Address to which the voting power of `_tokenId` is delegated.
     * @param _duration Amount of time to delegate voting power. Will be the expiration date for the new Delegator.
     * @return newDelegator -> Contract address of new Delegator beacon proxy.
     */
    function deployDelegator(uint256 _tokenId, address _delegatee, uint256 _duration) external nonReentrant returns (address newDelegator) {
        require(canDelegate[msg.sender] || msg.sender == owner(), "DelegateFactory: Not authorized");
        require(_delegatee != address(0), "delegatee cannot be address(0)");
        require(_duration != 0, "duration must be greater than 0");
        require(delegatorLimit > delegators.length, "delegator limit cannot be exceeded");

        // take token
        veRWA.transferFrom(msg.sender, address(this), _tokenId);

        // create delegator
        BeaconProxy newDelegatorBeacon = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(Delegator.initialize.selector,
                address(veRWA),
                msg.sender,
                _delegatee
            )
        );

        newDelegator = address(newDelegatorBeacon);

        delegators.push(newDelegator);
        indexInDelegators[newDelegator] = delegators.length - 1;
        isDelegator[newDelegator] = true;
        delegatorExpiration[newDelegator] = block.timestamp + _duration;

        // deposit token into delegator
        veRWA.approve(newDelegator, _tokenId);
        IDelegator(newDelegator).depositDelegatorToken(_tokenId);

        emit DelegatorCreated(newDelegator);
    }

    /**
     * @notice TODO
     */
    function revokeExpiredDelegators(address[] calldata _delegators) external nonReentrant { // TODO: Test
        // TODO: Check msg.sender is owner or wallet that delegated. Or should it be canDelegate?

        uint256 length = _delegators.length;
        for (uint256 i; i < length;) {
            address _delegator = _delegators[i];
            require(isDelegator[_delegator], "Invalid delegator");

            _revokeDelegator(_delegator);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method is used to fetch any expired Delegators, withdraw the delegated token from the Delegator,
     *         and delete it's instance from this contract.
     */
    function revokeAllExpiredDelegators() external nonReentrant {
        uint256 length = delegators.length;
        for (uint256 i; i < length;) {
            address delegator = delegators[i];
            if (isExpiredDelegator(delegator)) {
                _revokeDelegator(delegator);
                --length;
            }
            if (i < length) {
                if (!isExpiredDelegator(delegators[i])) {
                    unchecked {
                        ++i;
                    }
                }
            }
        }
    }

    /**
     * @notice Permissiond method to assign whether a `_delegatingEOA` address can deploy delegators.
     * @param _delegatingEOA Address being granted (or revoked) permission to delegate.
     * @param _canDelegate If true, `_delegatingEOA` can delegate.
     */
    function setCanDelegate(address _delegatingEOA, bool _canDelegate) external onlyOwner {
        emit DelegatorRoleSet(_delegatingEOA, _canDelegate);
        canDelegate[_delegatingEOA] = _canDelegate;
    }

    /**
     * @notice This function allows the factory owner to update the Delegator implementation.
     * @param _newDelegatorImp Address of new Delegator contract implementation.
     */
    function updateDelegatorImplementation(address _newDelegatorImp) external onlyOwner {
        beacon.upgradeTo(_newDelegatorImp);
    }

    /**
     * @notice This function allows the factory owner to update the delegatorLimit.
     * @param _newLimit New limit to how many delegators can be deployed at one time.
     */
    function updateDelegatorLimit(uint256 _newLimit) external onlyOwner {
        delegatorLimit = _newLimit;
    }

    /**
     * @notice This is an admin function that stores all addresses in the delegators array
     * with it's proper index value in indexInDelegators mapping.
     * @dev This is needed because the original implementation did not contain this storage mapping
     * so any existing delegators that have been deployed will not have a correct key-value pair in
     * the indexInDelegators mapping.
     */
    function initializeIndexInDelegators() external onlyOwner {
        uint256 length = delegators.length;
        for (uint256 i; i < length;) {
            indexInDelegators[delegators[i]] = i;
        }
    }

    /**
     * @notice This view method is used to fetch whether there exists any expired delegators.
     * @return exists -> True if expired delegator exists.
     */
    function expiredDelegatorExists() external view returns (bool exists) {
        for (uint256 i; i < delegators.length;) {
            if (isExpiredDelegator(delegators[i])) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /**
     * @notice Returns true if the specified address is an expired delegator contract.
     * @param _delegator address of delegator being queried.
     * @return expired -> True if `_delegator` is expired.
     */
    function isExpiredDelegator(address _delegator) public view returns (bool expired) {
        if (!isDelegator[_delegator]) return false;
        return block.timestamp >= delegatorExpiration[_delegator];
    }

    /**
     * @notice View method for fetching delegators array.
     * @return delegators array.
     */
    function getDelegatorsArray() external view returns (address[] memory) {
        return delegators;
    }

    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Withdraws delegated token from delegator contract back to the creator and deletes existance.
     */
    function _revokeDelegator(address _delegator) internal {
        emit DelegatorDeleted(_delegator);
        // call withdrawDelegatedToken
        IDelegator(_delegator).withdrawDelegatedToken();
        // delete delegator from contract
        delete isDelegator[_delegator];
        delete delegatorExpiration[_delegator];

        // delete from array
        uint256 len = delegators.length;
        uint256 index = indexInDelegators[_delegator];
        delete indexInDelegators[_delegator];
        if (index != (len - 1)) {
            indexInDelegators[delegators[len - 1]] = index;
            delegators[index] = delegators[len - 1];
        }
        delegators.pop();
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the DEFAULT_ADMIN_ROLE role to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}