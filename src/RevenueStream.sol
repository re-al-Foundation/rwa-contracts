// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Votes } from "@openzeppelin/contracts/governance/utils/Votes.sol";

// oz upgradeable imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// local imports
import { IRevenueStream } from "./interfaces/IRevenueStream.sol";

/**
 * @title RevenueStream
 * @author @chasebrownn
 * @notice This contract facilitates the distribution of claimable revenue to veRWA shareholders. 
 *         This contract will facilitate the distribution of only 1 ERC-20 revenue token.
 *         If there are several streams of ERC-20 revenue, it's suggested to deploy multiple RevenueStream contracts.
 */
contract RevenueStream is IRevenueStream, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------

    uint256 constant internal MAX_INT = type(uint256).max;
    /// @dev Contract reference for ERC-20 revenue token.
    IERC20 public immutable revenueToken;
    /// @dev Array used to track all deposits by timestamp.
    uint256[] public cycles;
    /// @dev The duration between deposit and when the revenue in the cycle becomes expired.
    uint256 public timeUntilExpired;
    /// @dev The last index in `cycles` that was skimmed for expired revenue.
    uint256 public expiredRevClaimedIndex;
    /// @dev Mapping from cycle to amount revenue deposited into contract.
    mapping(uint256 cycle => uint256 amount) public revenue;
    /// @dev Mapping from cycle to amount revenue claimed from cycle.
    mapping(uint256 cycle => uint256 amount) public revenueClaimed;
    /// @dev Mapping from cycle to whether the expired unclaimed revenue was claimed/skimmed.
    mapping(uint256 cycle => bool) public expiredRevClaimed;
    /// @dev Mapping of an account's last cycle claimed.
    mapping(address account => uint256 index) public lastClaimIndex;
    /// @dev Contract reference for veRWA contract.
    address public votingEscrow;
    /// @dev Stores the address of the RevenueDistributor contract.
    address public revenueDistributor;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted upon a successful execution of deposit().
     * @param amount Amount of `revenueToken` deposited.
     */
    event RevenueDeposited(uint256 amount);

    /**
     * @notice This event is emitted when revenue is claimed by an eligible shareholder.
     * @param claimer Address that claimed revenue.
     * @param cycle Cycle in which claim took place.
     * @param amount Amount of `revenueToken` claimed.
     */
    event RevenueClaimed(address indexed claimer, uint256 indexed cycle, uint256 amount);

    /**
     * @notice This event is emitted when expired revenue is skimmed and sent back to the RevenueDistributor.
     * @param amount Amount of revenue skimmed.
     * @param numCycles Number of "expired" cycles skimmed.
     */
    event ExpiredRevenueSkimmed(uint256 amount, uint256 numCycles);

    /**
     * @notice This event is emitted when a new `timeUntilExpired` is set.
     * @param newTimeUntilExpired New value stored in `timeUntilExpired`.
     */
    event TimeUntilExpiredSet(uint256 newTimeUntilExpired);

    
    // -----------
    // Constructor
    // -----------

    /**
     * @notice RevenueStream constructor
     * @param _revenueToken ERC-20 token to be assigned as RevenueStream's revenue token.
     */
    constructor(address _revenueToken) {
        require(_revenueToken != address(0));
        revenueToken = IERC20(_revenueToken);
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice Initializes RevenueStream
     * @param _distributor Contract address of RevenueDistributor contract.
     * @param _votingEscrow Contract address of VotingEscrow contract. Holders of VE tokens will be entitled to revenue shares.
     * @param _admin Address that will be granted initial ownership.
     */
    function initialize(
        address _distributor,
        address _votingEscrow,
        address _admin
    ) external initializer {
        require(_distributor != address(0));
        require(_votingEscrow != address(0));
        require(_admin != address(0));

        __Ownable_init(_admin);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        votingEscrow = _votingEscrow;
        revenueDistributor = _distributor;

        timeUntilExpired = 6 * (30 days); // 6 months to claim before expired
        cycles.push(1);
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method is used to deposit ERC-20 `revenueToken` into the contract to be claimed by shareholders.
     * @dev Can only be called by an address granted the `DEPOSITOR_ROLE`.
     * @param amount Amount of `revenueToken` to be deposited.
     */
    function deposit(uint256 amount) external {
        require(amount != 0, "RevenueStream: amount == 0");
        require(msg.sender == revenueDistributor, "RevenueStream: Not authorized");

        amount = _pullTokens(amount);

        if (revenue[block.timestamp] == 0) {
            cycles.push(block.timestamp);
            revenue[currentCycle()] = amount;
        }
        else {
            /// @dev In the event `deposit` is called twice in the same second (though unlikely), dont push a new cycle.
            ///      Just add the value to the existing cycle.
            revenue[block.timestamp] += amount;
        }

        emit RevenueDeposited(amount);
    }

    /**
     * @notice This method allows eligible VE shareholders to claim their revenue rewards.
     */
    function claim() external returns (uint256 amount) {
        amount = claimIncrement(MAX_INT);
    }

    /**
     * @notice This method allows eligible VE shareholders to claim their revenue rewards by account in increments by index.
     * @param numIndexes Number of revenue cycles the msg.sender wants to claim in one transaction.
     *        If the amount of cycles is substantial, it's recommended to claim in more than one increment.
     */
    function claimIncrement(uint256 numIndexes) public nonReentrant returns (uint256 amount) {
        require(numIndexes != 0, "RevenueStream: numIndexes cant be 0");

        uint256 cycle = currentCycle();

        uint256[] memory cyclesClaimable;
        uint256[] memory amountsClaimable;
        uint256 num;
        uint256 indexes;

        (amount, cyclesClaimable, amountsClaimable, num, indexes) = _claimable(msg.sender, numIndexes);
        require(amount > 0, "no claimable amount");

        lastClaimIndex[msg.sender] += indexes;

        for (uint256 i; i < num;) {
            revenueClaimed[cyclesClaimable[i]] += amountsClaimable[i];
            unchecked {
                ++i;
            }
        }

        revenueToken.safeTransfer(msg.sender, amount);

        emit RevenueClaimed(msg.sender, cycle, amount);
    }

    /**
     * @notice This method claims all "expired" revenue and sends it back to the RevenueDistributor contract.
     * @dev When revenue is "skimmed", it means it was expired revenue that was left unclaimed for more than the
     *      `timeUntilExpired` duration. If skimmed, it is sent back to the RevenueDistributor contract.
     * @return amount -> Amount of expired revenue that was skimmed.
     */
    function skimExpiredRevenue() external onlyOwner returns (uint256 amount) {
        return _skimExpiredRevenue(MAX_INT);
    }

    /**
     * @notice This method claims all "expired" revenue in increments starting from last claimed expired cycle.
     * @dev When revenue is "skimmed", it means it was expired revenue that was left unclaimed for more than the
     *      `timeUntilExpired` duration. If skimmed, it is sent back to the RevenueDistributor contract.
     * @return amount -> Amount of expired revenue that was skimmed.
     */
    function skimExpiredRevenueIncrement(uint256 numIndexes) external onlyOwner returns (uint256 amount) {
        require(numIndexes != 0, "RevenueStream: numIndexes cant be 0");
        return _skimExpiredRevenue(numIndexes);
    }

    /**
     * @notice This method allows a permissioned admin to update the `timeUntilExpired` variable.
     * @param _duration New duration until revenue is deemed "expired".
     */
    function setExpirationForRevenue(uint256 _duration) external onlyOwner {
        emit TimeUntilExpiredSet(_duration);
        timeUntilExpired = _duration;
    }

    /**
     * @notice View method that returns amount of revenue that is claimable, given a specific `account`.
     * @param account Address of shareholder.
     * @return amount Amount of revenue that is currently claimable.
     */
    function claimable(address account) external view returns (uint256 amount) {
        (amount,,,,) = _claimable(account, MAX_INT);
    }
    /**
     * @notice View method that returns amount of revenue that is claimable within a range of cycles, given a specific `account`
     *         and number of cycles/indexes you wish to increment over.
     * @param account Address of shareholder.
     * @param numIndexes Number of cycles to fetch claimable from.
     * @return amount Amount of revenue that is currently claimable.
     */
    function claimableIncrement(address account, uint256 numIndexes) external view returns (uint256 amount) {
        (amount,,,,) = _claimable(account, numIndexes);
    }

    /**
     * @notice This method returns the amount of "expired" revenue.
     * @return amount -> Amount of expired revenue in total.
     */
    function expiredRevenue() external view returns (uint256 amount) {
        (amount,,,) = _checkForExpiredRevenue(MAX_INT);
    }

    /**
     * @notice This method returns the amount of "expired" revenue.
     * @param numIndexes Number of cycles to fetch expired from last claim of expired revenue.
     * @return amount -> Amount of expired revenue in total.
     */
    function expiredRevenueIncrement(uint256 numIndexes) external view returns (uint256 amount) {
        (amount,,,) = _checkForExpiredRevenue(numIndexes);
    }

    /**
     * @notice View method that returns the `cycles` array.
     */
    function getCyclesArray() external view returns (uint256[] memory) {
        return cycles;
    }

    /**
     * @notice View method that returns the balance of revenueToken in this contract.
     */
    function getContractBalance() public view returns (uint256){
        return revenueToken.balanceOf(address(this));
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @notice Returns the most recent ("current") cycle.
     * @return cycle Last block.timestamp of most recent deposit.
     */
    function currentCycle() public view returns (uint256 cycle) {
        return cycles[cycles.length - 1];
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Internal method for skimming expired revenue.
     */
    function _skimExpiredRevenue(uint256 numIndexes) internal nonReentrant returns (uint256 amount) {
        uint256[] memory expiredCycles;
        uint256 num;
        uint256 indexes;
        // fetch any expired cycles.
        (amount, expiredCycles, num, indexes) = _checkForExpiredRevenue(numIndexes);
        require(amount > 0, "No expired revenue claimable");

        expiredRevClaimedIndex += indexes;

        // update `expiredRevClaimed` for each cycle being skimmed.
        for (uint256 i; i < num;) {
            expiredRevClaimed[expiredCycles[i]] = true;
            unchecked {
                ++i;
            }
        }

        // send tokens to revdist
        revenueToken.safeTransfer(revenueDistributor, amount);

        emit ExpiredRevenueSkimmed(amount, num);
    }

    /**
     * @notice Internal method for calculating the amount of revenue that is currently claimable for a specific `account`.
     * @dev To avoid the potential of a memory allocation error, the initial size of cyclesClaimable and amountsClaimable is
     * set to either numIndexes or cycles.length depending on which is lower.
     * @param account Address of account with voting power.
     * @return amount -> Amount of ERC-20 revenueToken that is currently claimable for `account`.
     */
    function _claimable(
        address account,
        uint256 numIndexes
    ) internal view returns (
        uint256 amount,
        uint256[] memory cyclesClaimable,
        uint256[] memory amountsClaimable,
        uint256 num,
        uint256 indexes
    ) {
        uint256 numCycles = cycles.length;
        uint256 lastClaim = lastClaimIndex[account];

        uint256 arrSize;
        numIndexes == MAX_INT ? arrSize = numCycles : arrSize = numIndexes;

        cyclesClaimable = new uint256[](arrSize);
        amountsClaimable = new uint256[](arrSize);

        for (uint256 i = lastClaim + 1; i < numCycles; ++i) {
            uint256 cycle = cycles[i];
            uint256 currentRevenue = revenue[cycle];

            uint256 votingPowerAtTime = Votes(votingEscrow).getPastVotes(account, cycle);
            uint256 totalPowerAtTime = Votes(votingEscrow).getPastTotalSupply(cycle);

            if (votingPowerAtTime != 0 && !expiredRevClaimed[cycle]) {
                uint256 claimableForCycle = (currentRevenue * votingPowerAtTime) / totalPowerAtTime;
                amount += claimableForCycle;

                cyclesClaimable[num] = cycle;
                amountsClaimable[num] = claimableForCycle;
                ++num;
            }

            unchecked {
                ++indexes;
                if (indexes >= numIndexes) break;
            }
        }
    }

    /**
     * @notice This method returns the amount of expired revenue along with expired cycles.
     * @dev To avoid the potential of a memory allocation error, the initial size of cyclesClaimable and amountsClaimable is
     * set to either numIndexes or cycles.length depending on which is lower.
     * @return expired -> Amount of expired revenue in total.
     * @return expiredCycles -> Array of cycles that contain expired revenue.
     * @return num -> Number of cycles in `expiredCycles`.
     * @return indexes -> Indexes reached.
     */
    function _checkForExpiredRevenue(uint256 numIndexes) internal view returns (uint256 expired, uint256[] memory expiredCycles, uint256 num, uint256 indexes) {
        uint256 numCycles = cycles.length;

        uint256 arrSize;
        numIndexes == MAX_INT ? arrSize = numCycles : arrSize = numIndexes;

        expiredCycles = new uint256[](arrSize);

        for (uint256 i = expiredRevClaimedIndex + 1; i < numCycles; ++i) {

            uint256 cycle = cycles[i];
            uint256 timePassed = block.timestamp - cycle; // seconds since cycle was created
            uint256 unclaimedRevenue = revenue[cycle] - revenueClaimed[cycle]; // revenue still to be claimed

            // If the cycle is expired and there's still revenue to be claimed...
            if (timePassed >= timeUntilExpired) {
                if (unclaimedRevenue != 0) {
                    // if there's unclaimed revenue in this cycle (that we know is expired),
                    // add that revenue to the `expired` value.
                    expired += unclaimedRevenue;

                    // add cycle to `expiredCycles` array.
                    expiredCycles[num] = cycle;
                    unchecked {
                        // increment `num`.
                        ++num;
                    }
                }
            }
            else {
                // If there's no more expired cycles, return with values.
                break;
            }

            unchecked {
                ++indexes;
                if (indexes >= numIndexes) break;
            }
        }

        return (expired, expiredCycles, num, indexes);
    }

    /**
     * @notice This internal method handles the transferring of tokens into this contrat during a deposit.
     * @dev This method monitors the contract balance before and after the transfer to catch any potential
     * rounding issue from rebase tokens.
     * @param amount Amount of tokens to transfer.
     * @return Amount of tokens received.
     */
    function _pullTokens(uint256 amount) internal returns (uint256) {
        uint256 preBal = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        return revenueToken.balanceOf(address(this)) - preBal;
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to owner
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}