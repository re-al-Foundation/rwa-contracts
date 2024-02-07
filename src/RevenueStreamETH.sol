// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Votes } from "@openzeppelin/contracts/governance/utils/Votes.sol";

// oz upgradeable imports
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { IRevenueStreamETH } from "./interfaces/IRevenueStreamETH.sol";

/**
 * @title RevenueStreamETH
 * @author @chasebrownn
 * @notice This contract facilitates the distribution of claimable revenue to veRWA shareholders.
 *         This contract will facilitate the distribution of ETH.
 */
contract RevenueStreamETH is IRevenueStreamETH, UUPSUpgradeable, AccessControlUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    /// @dev Role identifier for restricing access to claiming mechanisms.
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");
    /// @dev Role identifier for restricing access to deposit mechanisms.
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR");
    /// @dev Role identifier for restricing access to expired revenue skim mechanisms.
    bytes32 public constant SKIM_ROLE = keccak256("SKIM");
    /// @dev Array used to track all deposits by timestamp.
    uint256[] public cycles;
    /// @dev The duration between deposit and when the revenue in the cycle becomes expired.
    uint256 public timeUntilExpired;
    /// @dev Mapping from cycle to amount revenue deposited into contract.
    mapping(uint256 cycle => uint256 amount) public revenue;
    /// @dev Mapping from cycle to amount revenue claimed from cycle.
    mapping(uint256 cycle => uint256 amount) public revenueClaimed;
    /// @dev Mapping from cycle to whether the expired unclaimed revenue was claimed/skimmed.
    mapping(uint256 cycle => bool) public expiredRevClaimed;
    /// @dev Mapping of an account's last cycle claimed.
    mapping(address account => uint256 cycle) public lastClaim;
    /// @dev Contract reference for veRWA contract.
    address public votingEscrow;
    /// @dev Stores the address of the RevenueDistributor contract.
    address public revenueDistributor;


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
     * @param account Address that held the voting power.
     * @param cycle Cycle in which claim took place.
     * @param amount Amount of ETH claimed.
     */
    event RevenueClaimed(address indexed claimer, address indexed account, uint256 indexed cycle, uint256 amount);

    /**
     * @notice This event is emitted when expired revenue is skimmed and sent back to the RevenueDistributor.
     * @param amount Amount of ETH revenue skimmed.
     * @param numCycles Number of "expired" cycles skimmed.
     */
    event ExpiredRevenueSkimmed(uint256 amount, uint256 numCycles);


    // ------
    // Errors
    // ------

    /**
     * @notice This error is thrown when the transfer of ETH to the `recipient` fails.
     * @param recipient Intended receiver of ETH.
     * @param amount Amount of ETH sent.
     */
    error ETHTransferFailed(address recipient, uint256 amount);

    
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
     * @notice Initialized RevenueStream
     * @param _distributor Contract address of RevenueDistributor contract.
     * @param _votingEscrow Contract address of VotingEscrow contract. Holders of VE tokens will be entitled to revenue shares.
     * @param _admin Address that will be granted the `DEFAULY_ADMIN_ROLE` role.
     */
    function initialize(
        address _distributor,
        address _votingEscrow,
        address _admin
    ) external initializer {
        votingEscrow = _votingEscrow;
        revenueDistributor = _distributor;

        timeUntilExpired = 6 * (30 days); // 6 months to claim before expired

        cycles.push(block.timestamp);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SKIM_ROLE, _admin);
        _grantRole(DEPOSITOR_ROLE, _distributor);
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows address(this) to receive ETH.
     */
    receive() external payable {}

    /**
     * @notice This method is used to deposit ETH into the contract to be claimed by shareholders.
     * @dev Can only be called by an address granted the `DEPOSITOR_ROLE`.
     */
    function depositETH() payable external onlyRole(DEPOSITOR_ROLE) {
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
     * @notice This method allows eligible VE shareholders to claim their revenue rewards by account.
     * @param account Address of shareholder that is claiming rewards.
     */
    function claimETH(address account) external returns (uint256 amount) {
        require(account == msg.sender || hasRole(CLAIMER_ROLE, msg.sender), "unauthorized");

        uint256 cycle = currentCycle();

        uint256[] memory cyclesClaimable;
        uint256[] memory amountsClaimable;
        uint256 num;

        (amount, cyclesClaimable, amountsClaimable, num) = _claimable(account);

        require(amount > 0, "no claimable amount");

        lastClaim[account] = cycle;

        for (uint256 i; i < num;) {
            revenueClaimed[cyclesClaimable[i]] += amountsClaimable[i];
            unchecked {
                ++i;
            }
        }

        (bool sent,) = payable(msg.sender).call{value: amount}("");
        if (!sent) revert ETHTransferFailed(msg.sender, amount);

        emit RevenueClaimed(msg.sender, account, cycle, amount);
    }

    /**
     * @notice This method claims all "expired" revenue and sends it back to the RevenueDistributor contract.
     * @dev When revenue is "skimmed", it means it was expired revenue that was left unclaimed for more than the
     *      `timeUntilExpired` duration. If skimmed, it is sent back to the RevenueDistributor contract.
     * @return amount -> Amount of expired revenue that was skimmed.
     */
    function skimExpiredRevenue() external onlyRole(SKIM_ROLE) returns (uint256 amount) {
        uint256[] memory expiredCycles;
        uint256 num;
        // fetch any expired cycles.
        (amount, expiredCycles, num) = _checkForExpiredRevenue();
        require(amount > 0, "No expired revenue claimable");

        // update `expiredRevClaimed` for each cycle being skimmed.
        for (uint256 i; i < num;) {
            expiredRevClaimed[expiredCycles[i]] = true;
            unchecked {
                ++i;
            }
        }

        // send money to revdist
        (bool sent,) = payable(revenueDistributor).call{value: amount}("");
        if (!sent) revert ETHTransferFailed(revenueDistributor, amount);

        emit ExpiredRevenueSkimmed(amount, num);
    }

    /**
     * @notice This method allows a permissioned admin to update the `timeUntilExpired` variable.
     * @param _duration New duration until revenue is deemed "expired".
     */
    function setExpirationForRevenue(uint256 _duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        timeUntilExpired = _duration;
    }

    /**
     * @notice View method that returns amount of revenue that is claimable, given a specific `account`.
     * @param account Address of shareholder.
     * @return amount Amount of revenue that is currently claimable.
     */
    function claimable(address account) external view returns (uint256 amount) {
        (amount,,,) = _claimable(account);
    }

    /**
     * @notice This method returns the amount of "expired" revenue.
     * @return amount -> Amount of expired revenue in total.
     */
    function expiredRevenue() external view returns (uint256 amount) {
        (amount,,) = _checkForExpiredRevenue();
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
     * @notice Internal method for calculating the amount of revenue that is currently claimable for a specific `account`.
     * @param account Address of account with voting power.
     * @return amount -> Amount of ETH that is currently claimable for `account`.
     */
    function _claimable(
        address account
    ) internal view returns (
        uint256 amount,
        uint256[] memory cyclesClaimable,
        uint256[] memory amountsClaimable,
        uint256 num
    ) {
        uint256 numCycles = cycles.length;
        uint256 lastCycle = lastClaim[account];
        uint256 i = 1;
        uint256 cycle = cycles[numCycles - i];

        cyclesClaimable = new uint256[](numCycles);
        amountsClaimable = new uint256[](numCycles);

        while (i < numCycles && cycle > lastCycle) {
            uint256 currentRevenue = revenue[cycle];

            uint256 votingPowerAtTime = Votes(votingEscrow).getPastVotes(account, cycle);
            uint256 totalPowerAtTime = Votes(votingEscrow).getPastTotalSupply(cycle);

            if (votingPowerAtTime != 0 && !expiredRevClaimed[cycle]) {
                uint256 claimableForCycle = (currentRevenue * votingPowerAtTime) / totalPowerAtTime;
                amount += claimableForCycle;

                cyclesClaimable[i-1] = cycle;
                amountsClaimable[i-1] = claimableForCycle;
                ++num;
            }

            cycle = cycles[numCycles - (++i)];
        }
    }

    /**
     * @notice This method returns the amount of expired revenue along with expired cycles.
     * @return expired -> Amount of expired revenue in total.
     * @return expiredCycles -> Array of cycles that contain expired revenue.
     * @return num -> Number of cycles in `expiredCycles`.
     */
    function _checkForExpiredRevenue() internal view returns (uint256 expired, uint256[] memory expiredCycles, uint256 num) {
        uint256 numCycles = cycles.length;
        expiredCycles = new uint256[](numCycles);

        for (uint256 i = 1; i < numCycles;) {

            uint256 cycle = cycles[i];
            uint256 timePassed = block.timestamp - cycle; // seconds since cycle was created
            uint256 unclaimedRevenue = revenue[cycle] - revenueClaimed[cycle]; // revenue still to be claimed

            // If the cycle is expired and there's still revenue to be claimed...
            if (timePassed >= timeUntilExpired) {
                if (unclaimedRevenue != 0 && !expiredRevClaimed[cycle]) {
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
                return (expired, expiredCycles, num);
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}