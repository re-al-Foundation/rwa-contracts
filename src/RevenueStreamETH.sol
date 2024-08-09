// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Votes } from "@openzeppelin/contracts/governance/utils/Votes.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// oz upgradeable imports
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// local imports
import { IRevenueStreamETH } from "./interfaces/IRevenueStreamETH.sol";

/**
 * @title RevenueStreamETH
 * @author @chasebrownn
 * @notice This contract facilitates the distribution of claimable revenue to veRWA shareholders.
 *         This contract will facilitate the distribution of ETH.
 */
contract RevenueStreamETH is IRevenueStreamETH, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    uint256 constant internal MAX_INT = type(uint256).max;
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
    /// @dev Mapping of an account's last index claimed from the cycle array.
    mapping(address account => uint256 index) public lastClaimIndex;
    /// @dev Contract reference for veRWA contract.
    address public votingEscrow;
    /// @dev Stores the address of the RevenueDistributor contract.
    address public revenueDistributor;
    /// @dev Stores the address of a designated signer for verifying signature claims.
    address public signer;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted upon a successful execution of deposit().
     * @param amount Amount of ETH deposited.
     */
    event RevenueDeposited(uint256 amount);

    /**
     * @notice This event is emitted when revenue is claimed by an eligible shareholder.
     * @param claimer Address that claimed revenue.
     * @param amount Amount of ETH claimed.
     * @param indexes Amount of indexes claimed.
     */
    event RevenueClaimed(address indexed claimer, uint256 amount, uint256 indexes);

    /**
     * @notice This event is emitted when expired revenue is skimmed and sent back to the RevenueDistributor.
     * @param amount Amount of ETH revenue skimmed.
     * @param numCycles Number of "expired" cycles skimmed.
     */
    event ExpiredRevenueSkimmed(uint256 amount, uint256 numCycles);

    /**
     * @notice This event is emitted when a new `timeUntilExpired` is set.
     * @param newTimeUntilExpired New value stored in `timeUntilExpired`.
     */
    event TimeUntilExpiredSet(uint256 newTimeUntilExpired);

    /**
     * @notice This event is emitted when setSigner is executed.
     * @param newSigner New `signer` address.
     */
    event SignerSet(address indexed newSigner);


    // ------
    // Errors
    // ------

    /**
     * @notice This error is thrown when the transfer of ETH to the `recipient` fails.
     * @param recipient Intended receiver of ETH.
     * @param amount Amount of ETH sent.
     */
    error ETHTransferFailed(address recipient, uint256 amount);

    /**
     * @notice This error is thrown when an invalid address parameter is entered into a setter.
     */
    error InvalidAddress();

    /**
     * @notice This error is thrown when an invalid address parameter is entered into a setter.
     * @param recoveredSigner is the address fetched via ECDSA.recover when verifying a signature.
     */
    error InvalidSigner(address recoveredSigner);

    /**
     * @notice This error is thrown when an index provided to claimWithSignature does not match the current
     * last claimed index of the account.
     * @param account Account with an invalid index provided.
     * @param indexGiven The index provided.
     * @param lastClaimed The stored index in lastClaimedIndex[account].
     */
    error InvalidIndex(address account, uint256 indexGiven, uint256 lastClaimed);

    /**
     * @notice This error is thrown when a signature used in claimWithSignature is expired.
     * @param currentTimestamp Current timestamp when call is made.
     * @param deadline Timestamp when the signature was supposed to be used by.
     */
    error SignatureExpired(uint256 currentTimestamp, uint256 deadline);

    
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
     * @notice Initializes RevenueStreamETH
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
     * @notice This method is used to deposit ETH into the contract to be claimed by shareholders.
     * @dev Can only be called by an address granted the `DEPOSITOR_ROLE`.
     */
    function depositETH() payable external {
        require(msg.value != 0, "RevenueStreamETH: msg.value == 0");
        require(msg.sender == revenueDistributor, "RevenueStreamETH: Not authorized");

        if (revenue[block.timestamp] == 0) {
            cycles.push(block.timestamp);
            revenue[currentCycle()] = msg.value;
        }
        else {
            /// @dev In the event `depositETH` is called twice in the same second (though unlikely), dont push a new cycle.
            ///      Just add the value to the existing cycle.
            revenue[block.timestamp] += msg.value;
        }

        emit RevenueDeposited(msg.value);
    }

    /**
     * @notice This method allows eligible VE shareholders to claim their revenue rewards.
     */
    function claimETH() external returns (uint256 amount) {
        amount = claimETHIncrement(MAX_INT);
    }

    /**
     * @notice This method allows eligible VE shareholders to claim their revenue rewards by account in increments by index.
     * @param numIndexes Number of revenue cycles the msg.sender wants to claim in one transaction.
     *        If the amount of cycles is substantial, it's recommended to claim in more than one increment.
     */
    function claimETHIncrement(uint256 numIndexes) public nonReentrant returns (uint256 amount) {
        require(numIndexes != 0, "RevenueStreamETH: numIndexes cant be 0");

        uint256[] memory cyclesClaimable;
        uint256[] memory amountsClaimable;
        uint256 num;
        uint256 indexes;

        (amount, cyclesClaimable, amountsClaimable, num, indexes) = _claimable(msg.sender, numIndexes);

        lastClaimIndex[msg.sender] += indexes;

        for (uint256 i; i < num;) {
            revenueClaimed[cyclesClaimable[i]] += amountsClaimable[i];
            unchecked {
                ++i;
            }
        }

        _sendETH(msg.sender, amount);
        emit RevenueClaimed(msg.sender, amount, indexes);
    }
    
    /**
     * @notice This method allows an EOA to perform a claim with data that has been verified via a signature
     * from the dedicated `signer` address.
     * @param amount Amount of ETH being claimed.
     * @param currentIndex The current index of whicht the msg.sender last claimed.
     * @param indexes How many indexes (from cycles) we wish to cover in this claim.
     * @param cyclesClaimable Array of cycles we wish to claim from.
     * @param amountsClaimable Amounts being claimed in each cycle in cyclesClaimable.
     * @param num Length of cyclesClaimable & amountsClaimable.
     * @param signature Signature hash.
     */
    function claimWithSignature(
        uint256 amount,
        uint256 currentIndex,
        uint256 indexes,
        uint256[] calldata cyclesClaimable,
        uint256[] calldata amountsClaimable,
        uint256 num,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 data = keccak256(
            abi.encodePacked(
                msg.sender,
                amount,
                currentIndex,
                indexes,
                cyclesClaimable,
                amountsClaimable,
                num,
                deadline
            )
        );
        address messageSigner = ECDSA.recover(data, signature);

        // verify deadline
        if (block.timestamp > deadline) revert SignatureExpired(block.timestamp, deadline);

        // verify signer
        if (messageSigner != signer) revert InvalidSigner(messageSigner);

        // verify true lastClaimIndex == currentIndex
        uint256 lastClaimed = lastClaimIndex[msg.sender];
        if (lastClaimed != currentIndex) revert InvalidIndex(msg.sender, currentIndex, lastClaimed);

        // update lastClaimIndex
        lastClaimIndex[msg.sender] += indexes;

        // update revenueClaimed
        for (uint256 i; i < num;) {
            revenueClaimed[cyclesClaimable[i]] += amountsClaimable[i];
            unchecked {
                ++i;
            }
        }

        // transfer ETH to msg.sender
        _sendETH(msg.sender, amount);
        emit RevenueClaimed(msg.sender, amount, indexes);
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
        require(numIndexes != 0, "RevenueStreamETH: numIndexes cant be 0");
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
     * @notice This method allows a permissioned owner to update the `signer` address.
     * @param newSigner New address being used to sign claims.
     */
    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0) || newSigner == signer) revert InvalidAddress();
        emit SignerSet(newSigner);
        signer = newSigner;
    }

    /**
     * @notice View method that returns amount of revenue that is claimable, given a specific `account`.
     * @param account Address of shareholder.
     * @return amount Amount of revenue that is currently claimable.
     * @return cyclesClaimable Array of cycles that have claimable revenue for the account.
     * @return amountsClaimable Array of amounts of revenue that are claimable within the cycle. Indexes correspond with cyclesClaimable.
     * @return num Number of cycles that contain claimable revenue.
     * @return indexes Total indexes that have yet to be claimed or iterated over.
     */
    function claimable(address account) external view returns (
        uint256 amount,
        uint256[] memory cyclesClaimable,
        uint256[] memory amountsClaimable,
        uint256 num,
        uint256 indexes
    ) {
        (amount, cyclesClaimable, amountsClaimable, num, indexes) = _claimable(account, MAX_INT);
    }
    /**
     * @notice View method that returns amount of revenue that is claimable within a range of cycles, given a specific `account`
     *         and number of cycles/indexes you wish to increment over.
     * @param account Address of shareholder.
     * @param numIndexes Number of cycles to fetch claimable from.
     * @return amount Amount of revenue that is currently claimable.
     * @return cyclesClaimable Array of cycles that have claimable revenue for the account.
     * @return amountsClaimable Array of amounts of revenue that are claimable within the cycle. Indexes correspond with cyclesClaimable.
     * @return num Number of cycles that contain claimable revenue.
     * @return indexes Total indexes that have yet to be claimed or iterated over.
     */
    function claimableIncrement(address account, uint256 numIndexes) external view returns (
        uint256 amount,
        uint256[] memory cyclesClaimable,
        uint256[] memory amountsClaimable,
        uint256 num,
        uint256 indexes
    ) {
        (amount, cyclesClaimable, amountsClaimable, num, indexes) = _claimable(account, numIndexes);
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
     * @notice View method that returns the balance of ETH in this contract.
     */
    function getContractBalanceETH() public view returns (uint256){
        return address(this).balance;
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

        // send money to revdist
        _sendETH(revenueDistributor, amount);

        emit ExpiredRevenueSkimmed(amount, num);
    }

    /**
     * @notice Internal method for calculating the amount of revenue that is currently claimable for a specific `account`.
     * @dev To avoid the potential of a memory allocation error, the initial size of cyclesClaimable and amountsClaimable is
     * set to either numIndexes or cycles.length depending on which is lower.
     * @param account Address of account with voting power.
     * @return amount -> Amount of ETH that is currently claimable for `account`.
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

            if (votingPowerAtTime != 0 && !expiredRevClaimed[cycle]) {
                uint256 totalPowerAtTime = Votes(votingEscrow).getPastTotalSupply(cycle);
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
     * @notice This internal method is used to transfer ETH from this contract to a specified target address.
     * @param to Recipient address of ETH.
     * @param amount Amount of ETH to transfer.
     */
    function _sendETH(address to, uint256 amount) internal {
        (bool sent,) = payable(to).call{value: amount}("");
        if (!sent) revert ETHTransferFailed(to, amount);
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to owner
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}