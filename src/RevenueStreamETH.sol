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
 *         When claimable revenue is queried, the contrct will use the checkpoints unclaimed to calculate
 *         amount claimable for the account given their historical voting power ratio.
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
    /// @dev NO LONGER IN SERVICE
    mapping(uint256 cycle => uint256 amount) public revenueClaimed;
    /// @dev NO LONGER IN SERVICE
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
     * @notice This event is emitted when a new `timeUntilExpired` is set.
     * @param newTimeUntilExpired New value stored in `timeUntilExpired`.
     */
    event TimeUntilExpiredSet(uint256 newTimeUntilExpired);

    /**
     * @notice This event is emitted when setSigner is executed.
     * @param newSigner New `signer` address.
     */
    event SignerSet(address indexed newSigner);


    /**
     * @notice This event is emitted when recycleExpiredETH is executed.
     * @param amountETH Amount recycled.
     * @param upToIndex Expired revenue has been claimed up to this index in cycles.
     */
    event ExpiredRevenueRecycled(uint256 amountETH, uint256 upToIndex);


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

        uint256 indexes;
        (amount, indexes) = _claimable(msg.sender, numIndexes);

        lastClaimIndex[msg.sender] += indexes;

        _sendETH(msg.sender, amount);
        emit RevenueClaimed(msg.sender, amount, indexes);
    }
    
    /**
     * @notice This method allows an EOA to perform a claim with data that has been verified via a signature
     * from the dedicated `signer` address.
     * @param amount Amount of ETH being claimed.
     * @param currentIndex The current index of whicht the msg.sender last claimed.
     * @param indexes How many indexes (from cycles) we wish to cover in this claim.
     * @param deadline Timestamp signature must be used by until it's deemed expired/stale.
     * @param signature Signature hash.
     */
    function claimWithSignature(
        uint256 amount,
        uint256 currentIndex,
        uint256 indexes,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 data = keccak256(
            abi.encodePacked(
                msg.sender,
                amount,
                currentIndex,
                indexes,
                deadline
            )
        );
        address messageSigner = ECDSA.recover(getEthSignedMessageHash(data), signature);

        // verify deadline
        if (block.timestamp > deadline) revert SignatureExpired(block.timestamp, deadline);

        // verify signer
        if (messageSigner != signer) revert InvalidSigner(messageSigner);

        // verify true lastClaimIndex == currentIndex
        uint256 lastClaimed = lastClaimIndex[msg.sender];
        if (lastClaimed != currentIndex) revert InvalidIndex(msg.sender, currentIndex, lastClaimed);

        // update lastClaimIndex
        lastClaimIndex[msg.sender] += indexes;

        // transfer ETH to msg.sender
        _sendETH(msg.sender, amount);
        emit RevenueClaimed(msg.sender, amount, indexes);
    }

    /**
     * @notice This permissioned method is used to "recycle" expired ETH rewards from this contract.
     * @dev The ETH beign recycled is sent back to the RevenueDistributor contract for re-distribution.
     * @param amount Amount of ETH being recycled.
     * @param upToIndex Expired revenue has been expired up to this index in cycles.
     */
    function recycleExpiredETH(uint256 amount, uint256 upToIndex) external onlyOwner {
        require(amount != 0, "RevenueStreamETH: amount cant be 0");
        require(cycles.length >= upToIndex && upToIndex > expiredRevClaimedIndex, "RevenueStreamETH: upToIndex invalid range");

        emit ExpiredRevenueRecycled(amount, upToIndex);

        expiredRevClaimedIndex = upToIndex;
        _sendETH(revenueDistributor, amount);
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
     * @return indexes Total indexes that have yet to be claimed or iterated over.
     */
    function claimable(address account) external view returns (
        uint256 amount,
        uint256 indexes
    ) {
        (amount, indexes) = _claimable(account, MAX_INT);
    }
    /**
     * @notice View method that returns amount of revenue that is claimable within a range of cycles, given a specific `account`
     *         and number of cycles/indexes you wish to increment over.
     * @param account Address of shareholder.
     * @param numIndexes Number of cycles to fetch claimable from.
     * @return amount Amount of revenue that is currently claimable.
     * @return indexes Total indexes that have yet to be claimed or iterated over.
     */
    function claimableIncrement(address account, uint256 numIndexes) external view returns (
        uint256 amount,
        uint256 indexes
    ) {
        (amount, indexes) = _claimable(account, numIndexes);
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

    /**
     * @notice Appends an Eth header to the message hash and returns it as a new bytes array.
     */
    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Internal method for calculating the amount of revenue that is currently claimable for a specific `account`.
     * @dev We use a sliding window model to calculate amount claimable for an `account`. The beginning of the window is marked
     * by lastClaimIndex. In the event part of that revenue has been recycled (could occur if you wait too long to claim), the
     * beginning of the account's claimable window will be marked by expiredRevClaimedIndex (only in the event that 
     * expiredRevClaimedIndex > lastClaimIndex[account]).
     * @param account Address of account with voting power.
     * @return amount -> Amount of ETH that is currently claimable for `account`.
     * @return indexes -> The number of indexes that are unclaimed.
     */
    function _claimable( 
        address account,
        uint256 numIndexes
    ) internal view returns (
        uint256 amount,
        uint256 indexes
    ) {
        uint256 numCycles = cycles.length;
        uint256 lastClaim = lastClaimIndex[account];

        uint256 arrSize;
        numIndexes == MAX_INT ? arrSize = numCycles : arrSize = numIndexes;

        uint256 i = 1;
        if (expiredRevClaimedIndex > lastClaim) {
            i += expiredRevClaimedIndex;
            indexes += (expiredRevClaimedIndex - lastClaim);
        }
        else {
            i += lastClaim;
        }

        for (; i < numCycles; ++i) {
            uint256 cycle = cycles[i];
            uint256 currentRevenue = revenue[cycle];

            uint256 votingPowerAtTime = Votes(votingEscrow).getPastVotes(account, cycle);

            if (votingPowerAtTime != 0) {
                uint256 totalPowerAtTime = Votes(votingEscrow).getPastTotalSupply(cycle);
                uint256 claimableForCycle = (currentRevenue * votingPowerAtTime) / totalPowerAtTime;

                amount += claimableForCycle;
            }

            unchecked {
                ++indexes;
                if (indexes >= numIndexes) break;
            }
        }
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