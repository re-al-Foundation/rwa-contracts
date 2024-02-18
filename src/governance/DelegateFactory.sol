// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

// local imports
import { Delegator } from "./Delegator.sol";
import { FetchableBeaconProxy } from "../proxy/FetchableBeaconProxy.sol";

/**
 * @title DelegateFactory
 * @author @chasebrownn
 * @notice This contract acts as a factory for creating Delegator contracts.
 *         A permissioned admin can create delegator contracts to deposit Voting Escrow tokens to delegate voting power
 *         to a delegatee.
 */
contract DelegateFactory is UUPSUpgradeable, OwnableUpgradeable {

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


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when deployDelegator is executed.
     * @param _delegator New address of delegator.
     */
    event DelegatorCreated(address indexed _delegator);

    /**
     * @notice This event is emitted when revokeExpiredDelegators is executed for each expired Delegator.
     * @param _delegator Address of revoked delegator.
     */
    event DelegatorDeleted(address indexed _delegator);

    
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
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        veRWA = IERC721Enumerable(_veRWA);
        beacon = new UpgradeableBeacon(_initDelegatorBase, address(this));
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
    function deployDelegator(uint256 _tokenId, address _delegatee, uint256 _duration) external returns (address newDelegator) {
        require(canDelegate[msg.sender] || msg.sender == owner(), "DelegateFactory: Not authorized");

        // take token
        veRWA.safeTransferFrom(msg.sender, address(this), _tokenId);

        // create delegator
        FetchableBeaconProxy newDelegatorBeacon = new FetchableBeaconProxy(
            address(beacon),
            abi.encodeWithSelector(Delegator.initialize.selector,
                address(veRWA),
                msg.sender,
                _delegatee
            )
        );

        newDelegator = address(newDelegatorBeacon);

        delegators.push(newDelegator);
        isDelegator[newDelegator] = true;
        delegatorExpiration[newDelegator] = block.timestamp + _duration;

        // deposit token into delegator
        veRWA.approve(newDelegator, _tokenId);
        (bool success,) = newDelegator.call(abi.encodeWithSignature("depositDelegatorToken(uint256)", _tokenId));
        require(success, "deposit unsuccessful");

        emit DelegatorCreated(newDelegator);
    }

    /**
     * @notice This method is used to fetch any expired Delegators, withdraw the delegated token from the Delegator,
     *         and delete it's instance from this contract.
     */
    function revokeExpiredDelegators() external {
        uint256 length = delegators.length;
        for (uint256 i; i < length;) {
            address delegator = delegators[i];
            if (isExpiredDelegator(delegator)) {
                // call withdrawDelegatedToken
                (bool success,) = delegator.call(abi.encodeWithSignature("withdrawDelegatedToken()"));
                require(success, "withdraw unsuccessful");

                // delete delegator from contract
                delete isDelegator[delegator];
                delete delegatorExpiration[delegator];
                delegators[i] = delegators[length - 1];
                delegators.pop();
                --length;

                emit DelegatorDeleted(delegator);
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

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the DEFAULT_ADMIN_ROLE role to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}