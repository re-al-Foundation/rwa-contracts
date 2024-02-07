// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// oz upgradeable imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { IVotingEscrow } from "../interfaces/IVotingEscrow.sol";

/**
 * @title Voting Escrow Vesting
 * @author SeaZarrgh -> Refactored by Chase Brown
 * @notice The VotingEscrowVesting contract manages the vesting schedules for tokens locked in the VotingEscrow system.
 * It allows users to deposit their VotingEscrow tokens, undergo a vesting period, and then either withdraw them back or
 * claim the underlying locked tokens upon vesting completion.
 * @dev This contract uses the ReentrancyGuard to prevent reentrant calls. It interfaces with the VotingEscrow contract
 * to manage the locked tokens. The contract tracks vesting schedules and depositors' information, providing functions
 * to deposit, withdraw, and claim tokens based on their vesting schedules.
 *
 * Key Features:
 * - Deposit VotingEscrow tokens to start their vesting schedule.
 * - Withdraw VotingEscrow tokens back to the depositor after the vesting period.
 * - Claim the underlying locked tokens upon vesting completion, burning the VotingEscrow token.
 * - Manage vesting schedules and track depositors' vested tokens.
 */
contract VotingEscrowVesting is ReentrancyGuard, OwnableUpgradeable, UUPSUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    struct VestingSchedule {
        /// @dev lock epoch start time.
        uint256 startTime;
        /// @dev lock epoch end time.
        uint256 endTime;
        ///@dev amount of tokens locked.
        uint256 amount;
    }

    /// @dev Maps `owner` address to an array of tokenIds the address deposited into contract.
    mapping(address owner => uint256[]) public depositedTokens;
    /// @dev Maps `tokenId` to index of which token resides in depositedTokens array.
    mapping(uint256 tokenId => uint256) public depositedTokensIndex;
    /// @dev Maps `tokenId` to the token's vesting schedule.
    mapping(uint256 tokenId => VestingSchedule) public vestingSchedules;
    /// @dev Maps `tokenId` to the `owner` address that deposited token.
    mapping(uint256 tokenId => address owner) public depositors;
    /// @dev veRWA contract reference.
    IVotingEscrow public votingEscrow;


    // ------
    // Errors
    // ------

    /**
     * @notice Error emitted when an `account` tries to execute a permissioned method.
     * @param account Address that attempted the execution.
     */
    error NotAuthorized(address account);

    /**
     * @notice Error emitted when we try to access an index that is out of bounds.
     * @param depositor Address of owner.
     * @param index Invalid index argument.
     */
    error OutOfBoundsIndex(address depositor, uint256 index);


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
     * @notice Initializes VotingEscrowVesting
     * @param _admin Initial owner of this contract.
     */
    function initialize(address _admin) external initializer {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice ALlows owner to set `votingEscrow`.
     * @param _votingEscrow voting escrow contract address.
     */
    function setVotingEscrowContract(address _votingEscrow) external onlyOwner {
        votingEscrow = IVotingEscrow(_votingEscrow);
    }

    /**
     * @dev Deposits a VotingEscrow token to start its vesting schedule. The function records the vesting schedule,
     * removes the token's voting power, and transfers the token to this contract for vesting.
     *
     * @param tokenId The identifier of the VotingEscrow token to be deposited.
     * The vesting schedule is based on the remaining vesting duration and locked amount of the token.
     */
    function deposit(uint256 tokenId) external nonReentrant {
        uint256 duration = votingEscrow.getRemainingVestingDuration(tokenId);
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        uint256 amount = votingEscrow.getLockedAmount(tokenId);

        _addTokenToDepositorEnumeration(msg.sender, tokenId);
        // Store the vesting schedule for the token in `vestingSchedules`
        vestingSchedules[tokenId] = VestingSchedule(startTime, endTime, amount);
        // set new vesting duration to 0 on nft contract -> vesting contract should not have voting power
        votingEscrow.updateVestingDuration(tokenId, 0);
        // transfer NFT from depositor to this contract
        votingEscrow.transferFrom(msg.sender, address(this), tokenId);
    }

    /**
     * @dev Withdraws a VotingEscrow token back to the depositor after the vesting period. The function restores the
     * remaining vesting duration and transfers the token back to the depositor.
     *
     * @param receiver The address to receive the withdrawn VotingEscrow token.
     * @param tokenId The identifier of the VotingEscrow token to be withdrawn.
     */
    function withdraw(address receiver, uint256 tokenId) external nonReentrant {
        if (depositors[tokenId] != msg.sender) {
            revert NotAuthorized(msg.sender);
        }

        VestingSchedule storage tokenSchedule = vestingSchedules[tokenId];
        uint256 endTime = tokenSchedule.endTime;
        uint256 remainingTime;

        if (endTime > block.timestamp) {
            unchecked {
                remainingTime = endTime - block.timestamp;
            }
        }

        _removeTokenFromDepositorEnumeration(msg.sender, tokenId);

        delete vestingSchedules[tokenId];

        votingEscrow.updateVestingDuration(tokenId, remainingTime);
        votingEscrow.transferFrom(address(this), receiver, tokenId);
    }

    /**
     * @dev Claims the underlying locked tokens of a vested VotingEscrow token, effectively burning the VotingEscrow
     * token. The function can only be called once the vesting period has completed.
     *
     * @param receiver The address to receive the underlying locked tokens.
     * @param tokenId The identifier of the VotingEscrow token to be claimed.
     * The VotingEscrow token is burned, and the locked tokens are transferred to the receiver.
     */
    function claim(address receiver, uint256 tokenId) external nonReentrant {
        if (depositors[tokenId] != msg.sender) {
            revert NotAuthorized(msg.sender);
        }

        VestingSchedule storage tokenSchedule = vestingSchedules[tokenId];

        uint256 endTime = tokenSchedule.endTime;
        uint256 remainingTime;

        if (endTime > block.timestamp) {
            unchecked {
                remainingTime = endTime - block.timestamp;
            }
        }

        _removeTokenFromDepositorEnumeration(msg.sender, tokenId);

        delete vestingSchedules[tokenId];

        votingEscrow.updateVestingDuration(tokenId, remainingTime);
        votingEscrow.burn(receiver, tokenId);
    }

    /**
     * @dev Returns the number of VotingEscrow tokens deposited by a specific depositor.
     * @param depositor The address of the depositor whose balance is being queried.
     * @return The number of deposited tokens by the specified depositor.
     */
    function balanceOf(address depositor) external view returns (uint256) {
        return depositedTokens[depositor].length;
    }

    /**
     * @dev Retrieves the vesting schedule of a specific VotingEscrow token.
     * @param tokenId The identifier of the VotingEscrow token whose schedule is being queried.
     * @return The vesting schedule of the specified token, including start time, end time, and locked amount.
     */
    function getSchedule(uint256 tokenId) external view returns (VestingSchedule memory) {
        return vestingSchedules[tokenId];
    }

    /**
     * @dev Returns the identifier of a deposited VotingEscrow token owned by a depositor at a specific index.
     * @param depositor The address of the depositor whose token is being queried.
     * @param index The index in the depositor's list of deposited tokens.
     * @return The identifier of the deposited token at the specified index.
     * Throws if the index is out of bounds.
     */
    function tokenOfDepositorByIndex(address depositor, uint256 index) external view virtual returns (uint256) {
        uint256[] storage tokens = depositedTokens[depositor];
        if (index >= tokens.length) {
            revert OutOfBoundsIndex(depositor, index);
        }
        return tokens[index];
    }

    /**
     * @notice Method for fetching the deposited tokens of a given address.
     * @param account Address we wish to query deposited what array of tokens.
     */
    function getDepositedTokens(address account) external view returns (uint256[] memory) {
        return depositedTokens[account];
    }


    // ---------------
    // Private Methods
    // ---------------

    /**
     * @dev Internal function to add a token to the enumeration of tokens deposited by a specific depositor. It tracks
     * the deposit of a new VotingEscrow token.
     *
     * @param to The address of the depositor.
     * @param tokenId The identifier of the VotingEscrow token being deposited.
     */
    function _addTokenToDepositorEnumeration(address to, uint256 tokenId) private {
        uint256[] storage tokens = depositedTokens[to];
        depositors[tokenId] = to;
        depositedTokensIndex[tokenId] = tokens.length;
        tokens.push(tokenId);
    }

    /**
     * @dev Internal function to remove a token from the enumeration of tokens deposited by a specific depositor. It
     * handles the withdrawal or claiming of a VotingEscrow token.
     *
     * @param from The address of the depositor.
     * @param tokenId The identifier of the VotingEscrow token being withdrawn or claimed.
     */
    function _removeTokenFromDepositorEnumeration(address from, uint256 tokenId) private {
        uint256[] storage tokens = depositedTokens[from];

        uint256 lastTokenIndex = tokens.length - 1;
        uint256 tokenIndex = depositedTokensIndex[tokenId];

        assert(tokens[tokenIndex] == tokenId);

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = tokens[lastTokenIndex];
            tokens[tokenIndex] = lastTokenId;
            depositedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete depositors[tokenId];
        delete depositedTokensIndex[tokenId];

        tokens.pop();
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to owner
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
