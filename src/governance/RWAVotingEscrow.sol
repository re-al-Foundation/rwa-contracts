// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

// oz imports
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";

// oz upgradeable imports
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC721EnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

// local interfaces
import { IVotingEscrow } from "../interfaces/IVotingEscrow.sol";
import { IVoter } from "../interfaces/IVoter.sol";
import { IRWAToken } from "../interfaces/IRWAToken.sol";

// local libraries
import { VotingMath } from "./VotingMath.sol";
import { VotesUpgradeable } from "./utils/VotesUpgradeable.sol";

/**
 * @title Voting Escrow
 * @author SeaZarrgh -> Refactored by Daniel Kuppitz & Chase Brown
 * @notice VotingEscrow is an ERC721 token contract that assigns voting power based on the quantity of locked tokens and
 * their vesting duration. It is designed to incentivize long-term holding and participation in governance.
 * @dev The contract extends ERC721EnumerableUpgradeable for token enumeration, Ownable2StepUpgradeable for ownership
 * features, VotesUpgradeable for governance functionalities, and UUPSUpgradeable for upgradeability. It uses a
 * specialized storage structure to track locked balances, vesting durations, and voting power checkpoints.
 *
 * Key Features:
 * - ERC721 token representing locked tokens with vesting duration.
 * - Voting power calculation based on locked token amount and vesting duration.
 * - Functions to mint, burn, split, and merge locked token positions.
 * - Upgradeable contract design using UUPS pattern.
 *
 * The contract integrates with a Vesting contract to manage token vesting and voting power
 * updates, respectively, providing a flexible and robust governance token system.
 */
contract RWAVotingEscrow is ERC721EnumerableUpgradeable, Ownable2StepUpgradeable, VotesUpgradeable, UUPSUpgradeable, IVotingEscrow {
    using SafeERC20 for IERC20;
    using VotingMath for uint256;
    using Checkpoints for Checkpoints.Trace208;

    // ---------------
    // State Variables
    // ---------------

    /// @notice Stores the minimum vesting duration for a lock period.
    uint256 public constant MIN_VESTING_DURATION = 1 * (30 days);
    /// @notice Stores the maximum vesting duration for a lock period.
    uint256 public constant MAX_VESTING_DURATION = VotingMath.MAX_VESTING_DURATION;

    /// @custom:storage-location erc7201:veRWA.storage.VotingEscrow
    struct VotingEscrowStorage {
        /// @notice RealReceiver contract address. Facilitates migration messages.
        address endpointReceiver;
        /// @notice Max early-unlock fee.
        uint256 maxEarlyUnlockFee;
        /// @notice ERC-20 contract address of token. Default is $RWA token.
        IERC20 lockedToken;
        /// @notice VotingEscrowVesting contract address.
        address vestingContract;
        /// @notice Is used to create next tokenId for each NFT minted.
        uint256 tokenId;
        /// @notice Used to track total voting power in existance using checkpoints.
        Checkpoints.Trace208 _totalVotingPowerCheckpoints;
        /// @notice Used to track voting power of a token using checkpoints.
        mapping(uint256 tokenId => Checkpoints.Trace208) _votingPowerCheckpoints;
        /// @notice Used to track locked balance of `lockedToken` for each tokenId.
        mapping(uint256 tokenId => uint256) _lockedBalance;
        /// @notice Used to track remaining vesting duration of a given tokenId.
        mapping(uint256 tokenId => uint256) _remainingVestingDuration;
        /// @notice Used to track account voting power of each account.
        mapping(address account => uint256) _accountVotingPower;
        /// @notice Used to track the timestamp of which a tokenId was minted.
        mapping(uint256 tokenId => uint48) _mintingTimestamp;
        /// @notice Used to treack the default delegation for an account.
        mapping(address account => bool) _defaultDelegateSet;
    }

    // keccak256(abi.encode(uint256(keccak256("veRWA.storage.VotingEscrow")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VotingEscrowStorageLocation = 0xf51d083da217e6a6428a3c512c075d213d5e577bb6673abd7ff82c44dd93df00;


    // ------
    // Events
    // ------

    /**
     * @notice Event emitted when _createLock() is executed.
     * @param tokenId Token identifier of newly minted token.
     * @param lockedAmount Amount of `lockedToken` locked.
     * @param duration Duration of new lock.
     */
    event LockCreated(uint256 indexed tokenId, uint208 lockedAmount, uint256 duration);

    /**
     * @notice Event emitted when merge() is executed.
     * @param tokenId Token identifier of token being merged.
     * @param intoTokenId Token identifier of token that is consuming `tokenId`.
     */
    event LockMerged(uint256 indexed tokenId, uint256 indexed intoTokenId);

    /**
     * @notice Event emitted when split() is executed.
     * @param tokenId Token identifier of token being split.
     * @param shares An array of share proportions for splitting the token. 
     */
    event LockSplit(uint256 indexed tokenId, uint256[] shares);

    /**
     * @notice Event emitted when burn() is executed.
     * @param tokenId Token identifier of token burned.
     * @param remainingTime The remaining time left on lock. If > 0, there will be a penalty incurred by account.
     * @param fee The percentage used to calculate `penalty`.
     * @param penalty Amount of tokens being burned if the lock was destroyed earlier than promised duration.
     * @param unlocked Amount of tokens unlocked and therefore transferred to account.
     */
    event LockBurned(uint256 indexed tokenId, uint256 remainingTime, uint256 fee, uint256 penalty, uint256 unlocked);

    /**
     * @notice Event emitted when a successful migration is fulfilled.
     * @param migrator Account that migrated.
     * @param tokenId Token identifier minted to `migrator`.
     */
    event MigrationFulfilled(address indexed migrator, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when the vesting duration of a token is updated.
     * @param tokenId Token being manipulated.
     * @param vestingDuration New vesting duration that is set for token.
     */
    event VestingDurationUpdated(uint256 indexed tokenId, uint256 vestingDuration);

    /**
     * @notice This event is emitted when a new `endpointReceiver` is set.
     * @param newRealReceiver New address stored in `endpointReceiver`.
     */
    event RealReceiverSet(address indexed newRealReceiver);


    // ------
    // Errors
    // ------

    /**
     * @notice This error is emitted when the length of shares arg given to the split method is invalid.
     */
    error InvalidSharesLength();

    /**
     * @notice This error is emitted when the lock duration is invalid.
     * @param duration The desired duration of lock.
     * @param min The minimum allowed duration.
     * @param max The maximum allowed duration.
     */
    error InvalidVestingDuration(uint256 duration, uint256 min, uint256 max);

    /**
     * @notice This error is emitted when an address attempts to call a permissioned method.
     * @param account msg.sender of permissioned method.
     */
    error NotAuthorized(address account);

    /**
     * @notice This error is emitted when an account attempts to crate a lock with 0 locked balance.
     */
    error ZeroLockBalance();

    /**
     * @notice This error is emitted when a user atempts to merge a token into itself.
     */
    error SelfMerge();

    /**
     * @notice This error is emitted when a deposit is being made for a token with a remaining
     * vesting duration less than MIN_VESTING_DURATION.
     */
    error InsufficientVestingDuration(uint256 duration);

    /**
     * @notice This error is emitted if the amount of tokens transferred to this contract is not equal
     * to the amount of tokens received.
     * @param received The amount of tokens received.
     * @param intended The amount of tokens intended to receive.
     */
    error InsufficientTokenReceived(uint256 received, uint256 intended);


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
     * @dev Initializes the VotingEscrow contract, setting up ERC721 metadata and ownership, along with the initial
     * vesting contract and voter contract addresses.
     * @param _lockedToken Contract addres for locked token.
     * @param _vestingContract The address of the contract managing token vesting.
     * @param _endpoint The local address of the RealReceiver contract.
     * @param _admin The assigned owner of this contract.
     */
    function initialize(address _lockedToken, address _vestingContract, address _endpoint, address _admin) external initializer {
        require(_lockedToken != address(0), "address(0) is not acceptable for lockedToken");
        require(_vestingContract != address(0), "address(0) is not acceptable for vesting contract");
        require(_admin != address(0), "address(0) is not acceptable for admin");

        __ERC721_init("RWA Voting Escrow", "veRWA");
        __Ownable_init(_admin);
        __Votes_init();
        __UUPSUpgradeable_init();

        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $.lockedToken = IERC20(_lockedToken);
        $.vestingContract = _vestingContract;
        $.endpointReceiver = _endpoint;
        $.maxEarlyUnlockFee = 50 * 1e18; // 50%
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @dev Mints a new VotingEscrow token representing a locked token position. The minting process locks a specified
     * amount of tokens for a given vesting duration, assigning voting power accordingly.
     * @param _receiver The address that will receive the minted VotingEscrow token.
     * @param _lockedBalance The amount of tokens to be locked.
     * @param _duration The duration for which the tokens will be locked.
     * @return tokenId The unique identifier for the minted VotingEscrow token.
     */
    function mint(address _receiver, uint208 _lockedBalance, uint256 _duration) external returns (uint256 tokenId) {
        // if _lockedBalance is 0, revert
        if (_lockedBalance == 0) revert ZeroLockBalance();
        // if _duration is not within range, revert
        if (_duration < MIN_VESTING_DURATION || _duration > MAX_VESTING_DURATION) {
            revert InvalidVestingDuration(_duration, MIN_VESTING_DURATION, MAX_VESTING_DURATION);
        }

        // create lock
        tokenId = _createLock(_receiver, _lockedBalance, _duration);

        // get storage
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        // transfers tokens to this contract
        _pullTokens($.lockedToken, _msgSender(), _lockedBalance);
    }

    /**
     * @notice This method is called by the RealReceiver contract to fulfill the cross-chain migration from 3,3+ to veRWA.
     * @param _receiver The account being minted a new token.
     * @param _lockedBalance Amount of tokens to lock in new lock.
     * @param _duration Duration of new lock in seconds.
     * @return tokenId -> Token identifier minted to `_receiver`.
     */
    function migrate(address _receiver, uint256 _lockedBalance, uint256 _duration) external returns (uint256 tokenId) {
        // get storage
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        // msg.sender must be endpoint receiver
        if (msg.sender != $.endpointReceiver) revert NotAuthorized(msg.sender);

        // create lock
        tokenId = _createLock(_receiver, uint208(_lockedBalance), _duration);

        // mints tokens to this contract
        IRWAToken(address($.lockedToken)).mint(_lockedBalance);

        emit MigrationFulfilled(_receiver, tokenId);
    }

    /**
     * @notice This method is called by the RealReceiver contract to fulfill the cross-chain migration of a batch of 3,3+ NFTs to veRWA NFTs.
     * @param _receiver The account being minted a batch of new tokens.
     * @param _lockedBalances Array of amounts of tokens to lock in new locks.
     * @param _durations Array of durations of new locks (in seconds). Indexes correspond with `_lockedBalances`.
     * @return tokenIds -> Token identifiers minted to `_receiver`.
     */
    function migrateBatch(address _receiver, uint256[] memory _lockedBalances, uint256[] memory _durations) external returns (uint256[] memory tokenIds) {
        // get storage
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        // msg.sender must be endpoint receiver
        if (msg.sender != $.endpointReceiver) revert NotAuthorized(msg.sender);

        uint256 len = _lockedBalances.length;
        tokenIds = new uint256[](len);

        for (uint256 i; i < len;) {

            // create lock
            tokenIds[i] = _createLock(_receiver, uint208(_lockedBalances[i]), _durations[i]);

            // mints tokens to this contract
            IRWAToken(address($.lockedToken)).mint(_lockedBalances[i]);

            emit MigrationFulfilled(_receiver, tokenIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Burns a VotingEscrow token, releasing the locked tokens to the specified receiver. The burning process can
     * only be done once the vesting duration has finished.
     *
     * @param receiver The address to receive the released tokens.
     * @param tokenId The identifier of the VotingEscrow token to be burned.
     */
    function burn(address receiver, uint256 tokenId) external {
        _checkAuthorized(_requireOwned(tokenId), msg.sender, tokenId);

        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint256 remainingTime = $._remainingVestingDuration[tokenId];
        uint256 payout = $._lockedBalance[tokenId];

        _updateLock(tokenId, 0, 0);
        _burn(tokenId);

        uint256 fee;
        uint256 penalty;
        if (remainingTime != 0) {
            // calculate early unlock tax
            fee = _calculateEarlyFee(remainingTime);
            penalty = (payout * fee) / (100 * 1e18);

            payout = payout - penalty;

            // burn penalty
            IRWAToken(address($.lockedToken)).burn(penalty);
        }
        $.lockedToken.safeTransfer(receiver, payout);
        emit LockBurned(tokenId, remainingTime, fee, penalty, payout);
    }

    /**
     * @dev Deposits additional tokens for a specific VotingEscrow token, effectively increasing the locked balance and
     * potentially the voting power of the token holder.
     *
     * @param tokenId The identifier of the VotingEscrow token for which the deposit is being made.
     * @param amount The amount of additional tokens to be deposited and locked.
     */
    function depositFor(uint256 tokenId, uint256 amount) external {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint256 remainingVestingDuration = $._remainingVestingDuration[tokenId];
        if (remainingVestingDuration < MIN_VESTING_DURATION) {
            revert InsufficientVestingDuration(remainingVestingDuration);
        }
        _updateLock(tokenId, $._lockedBalance[tokenId] + amount, $._remainingVestingDuration[tokenId]);
        _pullTokens($.lockedToken, _msgSender(), amount);
    }

    /**
     * @dev Merges two VotingEscrow tokens into one, combining their locked balances and vesting durations.
     * The merge process adjusts the voting power based on the new combined balance and vesting duration.
     *
     * @param tokenId The identifier of the VotingEscrow token to be merged.
     * @param intoTokenId The identifier of the VotingEscrow token that tokenId will be merged into.
     */
    function merge(uint256 tokenId, uint256 intoTokenId) external {
        if (tokenId == intoTokenId) revert SelfMerge();

        address owner = _requireOwned(tokenId);
        address targetOwner = _requireOwned(intoTokenId);

        _checkAuthorized(owner, _msgSender(), tokenId);
        _checkAuthorized(targetOwner, _msgSender(), intoTokenId);

        VotingEscrowStorage storage $ = _getVotingEscrowStorage();

        uint256 combinedLockBalance = $._lockedBalance[tokenId] + $._lockedBalance[intoTokenId];
        uint256 remainingVestingDuration =
            Math.max($._remainingVestingDuration[tokenId], $._remainingVestingDuration[intoTokenId]);

        _updateLock(tokenId, 0, 0);
        _updateLock(intoTokenId, combinedLockBalance, remainingVestingDuration);

        _burn(tokenId);
        emit LockMerged(tokenId, intoTokenId);
    }

    /**
     * @notice Splits a VotingEscrow token into multiple tokens based on specified shares. The split process divides the
     *         locked balance and retains the original vesting duration for each new token.
     *
     * @dev The first element in `shares` will be the remaining proportion left in the already existing token, `tokenId`.
     *      The amount of new tokens minted is == shares.length - 1. The first element in the `tokenIds` array will always
     *      be the original `tokenId` used to create the split.
     *
     * @param tokenId The identifier of the VotingEscrow token to be split.
     * @param shares An array of share proportions for splitting the token.
     * @return tokenIds An array of newly minted token identifiers (excluding index 0) resulting from the split.
     */
    function split(uint256 tokenId, uint256[] calldata shares) external returns (uint256[] memory tokenIds) {
        uint256 len = shares.length;
        // If there is not 2 or more shares, revert
        if (len < 2) revert InvalidSharesLength();
        // fetch owner of tokenId being split
        address owner = _requireOwned(tokenId);
        // verify ownership of token
        _checkAuthorized(owner, _msgSender(), tokenId);
        // create array to store all newly minted tokenIds
        tokenIds = new uint256[](len);
        tokenIds[0] = tokenId;
        // find total shares from shares array
        uint256 totalShares;
        for (uint256 i = len; i != 0;) {
            unchecked {
                --i;
            }
            totalShares += shares[i];
        }

        // fetch voting escrow data storage
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        // fetch remaining duration of tokenId
        uint256 remainingVestingDuration = $._remainingVestingDuration[tokenId];
        // fetch lockedBalance of tokenId
        uint256 lockedBalance = $._lockedBalance[tokenId];
        if (lockedBalance == 0) revert ZeroLockBalance();
        // store lockedBalance in another var (will be used later)
        uint256 remainingBalance = lockedBalance;
        // find timestamp of current block
        uint48 mintingTimestamp = clock();
        // start iterating through shares array
        for (uint256 i = 1; i < len;) {
            // grab current share
            uint256 share = shares[i];
            // locked balance for this NFT is percentage of shares * total locked balance
            uint256 _lockedBalance = share * lockedBalance / totalShares;
            if (_lockedBalance == 0) revert ZeroLockBalance();
            // fetch new tokenId to mint
            uint256 newTokenId = _incrementAndGetTokenId();
            // store new tokenId in tokenIds array
            tokenIds[i] = newTokenId;
            // store timeststamp for new token
            $._mintingTimestamp[newTokenId] = mintingTimestamp;
            // mint new token
            _mint(owner, newTokenId);
            if (owner != msg.sender && !_isAuthorized(owner, msg.sender, newTokenId)) {
                _approve(msg.sender, newTokenId, owner);
            }
            // update lock info for new token
            _updateLock(newTokenId, _lockedBalance, remainingVestingDuration);
            // subtract locked balance from total balance
            unchecked {
                remainingBalance -= _lockedBalance;
                ++i;
            }
        }
        if (remainingBalance == 0) revert ZeroLockBalance();
        // update old token with remaining balance
        _updateLock(tokenId, remainingBalance, remainingVestingDuration);
        emit LockSplit (tokenId, shares);
    }

    /**
     * @dev Updates the vesting duration for a specific VotingEscrow token. This function can either shorten or extend
     * the vesting duration, affecting the token's voting power.
     *
     * @param tokenId The identifier of the VotingEscrow token whose vesting duration is being updated.
     * @param vestingDuration The new vesting duration for the token.
     */
    function updateVestingDuration(uint256 tokenId, uint256 vestingDuration) external {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint256 remainingVestingDuration = $._remainingVestingDuration[tokenId];
        if (vestingDuration < remainingVestingDuration) {
            if ($.vestingContract != _msgSender()) {
                revert InvalidVestingDuration(vestingDuration, remainingVestingDuration, MAX_VESTING_DURATION);
            }
        } else {
            if (vestingDuration > MAX_VESTING_DURATION) {
                revert InvalidVestingDuration(vestingDuration, remainingVestingDuration, MAX_VESTING_DURATION);
            }
            _checkAuthorized(ownerOf(tokenId), _msgSender(), tokenId);
        }
        _updateLock(tokenId, $._lockedBalance[tokenId], vestingDuration);
        emit VestingDurationUpdated(tokenId, vestingDuration);
    }

    /**
     * @notice Allows permissioned acount (owner) to update the RealReceiver address.
     * @param _newEndpointReceiver New address for RealReceiver.
     */
    function updateEndpointReceiver(address _newEndpointReceiver) external onlyOwner {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        emit RealReceiverSet(_newEndpointReceiver);
        $.endpointReceiver = _newEndpointReceiver;
    }

    /**
     * @notice Returns the most recent checkpoint (given a timestamp) for total voting power.
     * @param timepoint Timestamp of when to query most recent total voting power.
     */
    function getPastTotalVotingPower(uint256 timepoint) external view returns (uint256) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return $._totalVotingPowerCheckpoints.upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    /**
     * @notice Returns the most recent voting power checkpoint (given a timestamp) for a specific tokenId.
     * @param tokenId TokenId with historic voting power being fetched.
     * @param timepoint Timestamp of when to query most recent voting power for token.
     */
    function getPastVotingPower(uint256 tokenId, uint256 timepoint) external view returns (uint256) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return $._votingPowerCheckpoints[tokenId].upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    function getTokenId() external view returns (uint256) {
        return _getVotingEscrowStorage().tokenId;
    }

    function getLockedToken() external view returns (IERC20) {
        return _getVotingEscrowStorage().lockedToken;
    }

    function getVotingPowerCheckpoints(uint256 tokenId) external view returns (Checkpoints.Trace208 memory) {
        return _getVotingEscrowStorage()._votingPowerCheckpoints[tokenId];
    }

    function getTotalVotingPowerCheckpoints() external view returns (Checkpoints.Trace208 memory) {
        return _getVotingEscrowStorage()._totalVotingPowerCheckpoints;
    }

    function getAccountVotingPower(address account) external view returns (uint256) {
        return _getVotingEscrowStorage()._accountVotingPower[account];
    }

    function vestingContract() external view returns (address) {
        return _getVotingEscrowStorage().vestingContract;
    }

    function getLockedAmount(uint256 tokenId) external view returns (uint256) {
        return _getVotingEscrowStorage()._lockedBalance[tokenId];
    }

    function getMintingTimestamp(uint256 tokenId) external view returns (uint256) {
        return _getVotingEscrowStorage()._mintingTimestamp[tokenId];
    }

    function getRemainingVestingDuration(uint256 tokenId) external view returns (uint256) {
        return _getVotingEscrowStorage()._remainingVestingDuration[tokenId];
    }

    function getMaxEarlyUnlockFee() external view returns (uint256) {
        return _getVotingEscrowStorage().maxEarlyUnlockFee;
    }

    function getEndpointReceiver() external view returns (address) {
        return _getVotingEscrowStorage().endpointReceiver;
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @notice Returns the current block.timestamp.
     */
    function clock() public view virtual override returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure virtual override returns (string memory) {
        return "mode=timestamp";
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @dev Internal function to update the lock parameters of a specific VotingEscrow token. It adjusts the locked
     * balance, the vesting duration, and recalculates the voting power.
     *
     * @param tokenId The identifier of the VotingEscrow token being updated.
     * @param _lockedBalance The new locked balance for the token.
     * @param vestingDuration The new vesting duration for the token.
     */
    function _updateLock(uint256 tokenId, uint256 _lockedBalance, uint256 vestingDuration) internal {
        // get storage
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();

        // get owner of tokenId
        address owner = _requireOwned(tokenId);
        // get timestamp
        uint48 timepoint = SafeCast.toUint48(clock());
        // get latest voting power for tokenId
        uint208 votingPowerBefore = $._votingPowerCheckpoints[tokenId].latest();
        // calculate voting power with duration and locked balance
        uint208 votingPower = SafeCast.toUint208(_lockedBalance.calculateVotingPower(vestingDuration));
        // get locked balance before this lock, usually 0 unless re-lock.
        uint256 lockedBalanceBefore = $._lockedBalance[tokenId];

        // if locked balance is not equal to what's already locked, set amount
        if (_lockedBalance != lockedBalanceBefore) {
            $._lockedBalance[tokenId] = _lockedBalance;
        }

        // if voting power before is not equal to the new voting power...
        if (votingPower != votingPowerBefore) {
            // add timestamp and voting power to checkpoint
            $._votingPowerCheckpoints[tokenId].push(timepoint, votingPower);
            // get latest total voting power
            uint208 totalVotingPower = $._totalVotingPowerCheckpoints.latest();
            // store new total
            $._totalVotingPowerCheckpoints.push(timepoint, totalVotingPower - votingPowerBefore + votingPower);
        }

        // store vesting duration in full
        $._remainingVestingDuration[tokenId] = vestingDuration;

        // Update new voting power
        if (votingPowerBefore < votingPower) {
            unchecked {
                _transferVotingUnits(address(0), owner, votingPower - votingPowerBefore);
            }
        } else if (votingPowerBefore > votingPower) {
            unchecked {
                _transferVotingUnits(owner, address(0), votingPowerBefore - votingPower);
            }
        }
    }

    /**
     * @dev Internal method used for creating another lock instance.
     *
     * @param _receiver Account that will receive newly minted NFT.
     * @param _lockedBalance Amount of tokens being locked.
     * @param _duration Duration of time to lock tokens.
     * @return tokenId -> Token identifier of newly minted token.
     */
    function _createLock(address _receiver, uint208 _lockedBalance, uint256 _duration) internal returns (uint256 tokenId) {
        // increment tokenId
        tokenId = _incrementAndGetTokenId();
        // get storage
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        // store timestamp when lock was created
        $._mintingTimestamp[tokenId] = clock();
        // mint new NFT
        _mint(_receiver, tokenId);
        // updates || creates lock instance
        _updateLock(tokenId, _lockedBalance, _duration);

        emit LockCreated(tokenId, _lockedBalance, _duration);
    }

    /**
     * @dev Internal function to transfer voting units from one account to another. This function is called during token
     * transfers, minting, burning, and other operations that affect voting power.
     *
     * @param from The address from which the voting units are transferred.
     * @param to The address to which the voting units are transferred.
     * @param amount The amount of voting units being transferred.
     */
    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual override {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        if (from != address(0)) {
            $._accountVotingPower[from] -= amount;
        }
        if (to != address(0)) {
            $._accountVotingPower[to] += amount;
        }
        super._transferVotingUnits(from, to, amount);
    }

    /**
     * @dev Internal function to update the state during token transfers. It ensures the correct transfer of voting
     * units and updates delegate settings.
     *
     * @param to The address receiving the token.
     * @param tokenId The identifier of the VotingEscrow token being transferred.
     * @param auth The address authorized to perform the update.
     * @return The previous owner of the token.
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        address previousOwner = super._update(to, tokenId, auth);

        _setDefaultDelegate(to);
        _transferVotingUnits(previousOwner, to, $._votingPowerCheckpoints[tokenId].latest());

        return previousOwner;
    }

    /**
     * @dev Delegates voting power of one account to another.
     *
     * @param account Account delegating voting power to `delegatee`.
     * @param delegatee Account receiving the voting power of `account`.
     */
    function _delegate(address account, address delegatee) internal virtual override {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        if (!$._defaultDelegateSet[account]) {
            $._defaultDelegateSet[account] = true;
        }
        super._delegate(account, delegatee);
    }

    /**
     * @dev Internal method for setting a default delegate.
     *
     * @param account Account to set default delegate of `account` to `account`.
     */
    function _setDefaultDelegate(address account) internal virtual {
        if (_msgSender() == address(0)) return;
        if (_getVotingEscrowStorage()._defaultDelegateSet[account]) return;
        _delegate(account, account);
    }

    /**
     * @dev Overrides VotesUpgradeable::_getVotingUnits. Used for fetching voting units for `account`.
     *
     * @param account Voting power being fetched.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        return $._accountVotingPower[account];
    }

    /**
     * @dev Internal method for incrementing state variable `VotingEscrowStorage::tokenId`.
     *
     * @return tokenId -> tokenId post-increment.
     */
    function _incrementAndGetTokenId() internal returns (uint256 tokenId) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $.tokenId = (tokenId = $.tokenId + 1);
    }

    /**
     * @dev Internal method for calculating unlock-early fee.
     * @param _duration Duration of lock when `burn` is executed.
     *
     * @return fee -> Penalty fee calculated.
     */
    function _calculateEarlyFee(uint256 _duration) internal view returns (uint256 fee) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        fee = ($.maxEarlyUnlockFee * _duration) / MAX_VESTING_DURATION;
    }

    /**
     * @notice This internal method is used to move tokens from an address to this contract.
     * @dev This method performs a pre-state balance check and a post-state balance check to verify the amount
     * of tokens transferred is the exact amount that is received.
     * @param token ERC-20 token being transferred.
     * @param from Sender of tokens.
     * @param amount Amount of tokens being transferred to this contract.
     * @return amountReceived -> Amount of tokens received. If not equal to `amount`, function will revert.
     */
    function _pullTokens(IERC20 token, address from, uint256 amount) internal returns (uint256 amountReceived) {
        uint256 preBal = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        amountReceived = token.balanceOf(address(this)) - preBal;
        if (amount != amountReceived) revert InsufficientTokenReceived(amountReceived, amount);
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // --------------
    // Storage Getter
    // --------------

    /// @dev Returns storage slot for VotingEscrowStorage.
    function _getVotingEscrowStorage() private pure returns (VotingEscrowStorage storage $) {
        assembly {
            $.slot := VotingEscrowStorageLocation
        }
    }
}
