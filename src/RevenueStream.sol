// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Votes } from "@openzeppelin/contracts/governance/utils/Votes.sol";

// oz upgradeable imports
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { IRevenueStream } from "./interfaces/IRevenueStream.sol";

/**
 * @title RevenueStream
 * @author @chasebrownn
 * @notice This contract facilitates the distribution of claimable revenue to veRWA shareholders. 
 *         This contract will facilitate the distribution of only 1 ERC-20 revenue token.
 *         If there are several streams of ERC-20 revenue, it's suggested to deploy multiple RevenueStream contracts.
 */
contract RevenueStream is IRevenueStream, UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------

    /// @dev Role identifier for restricing access to claiming mechanisms.
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");
    /// @dev Role identifier for restricing access to deposit mechanisms.
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR");
    /// @dev Array used to track all deposits by timestamp.
    uint256[] public cycles;
    /// @dev Mapping from cycle to amount revenue deposited into contract.
    mapping(uint256 cycle => uint256 amount) public revenue;
    /// @dev Mapping of an account's last cycle claimed.
    mapping(address account => uint256 cycle) public lastClaim;
    /// @dev Contract reference for ERC-20 revenue token.
    IERC20 public revenueToken;
    /// @dev Contract reference for veRWA contract.
    address public votingEscrow;


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
     * @param account Address that held the voting power.
     * @param cycle Cycle in which claim took place.
     * @param amount Amount of `revenueToken` claimed.
     */
    event RevenueClaimed(address indexed claimer, address indexed account, uint256 indexed cycle, uint256 amount);

    
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
     * @param _revenueToken ERC-20 token to be assigned as RevenueStream's revenue token.
     * @param _distributor Contract address of RevenueDistributor contract.
     * @param _votingEscrow Contract address of VotingEscrow contract. Holders of VE tokens will be entitled to revenue shares.
     * @param _admin Address that will be granted the `DEFAULY_ADMIN_ROLE` role.
     */
    function initialize(
        address _revenueToken,
        address _distributor,
        address _votingEscrow,
        address _admin
    ) external initializer {
        revenueToken = IERC20(_revenueToken);
        votingEscrow = _votingEscrow;

        cycles.push(block.timestamp);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DEPOSITOR_ROLE, _distributor);
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method is used to deposit ERC-20 `revenueToken` into the contract to be claimed by shareholders.
     * @dev Can only be called by an address granted the `DEPOSITOR_ROLE`.
     * @param amount Amount of `revenueToken` to be deposited.
     */
    function deposit(uint256 amount) external onlyRole(DEPOSITOR_ROLE) {
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);

        cycles.push(block.timestamp);
        revenue[currentCycle()] = amount;

        emit RevenueDeposited(amount);
    }

    /**
     * @notice This method allows eligible VE shareholders to claim their revenue rewards by account.
     * @param account Address of shareholder that is claiming rewards.
     */
    function claim(address account) external returns (uint256 amount) {
        require(account == msg.sender || hasRole(CLAIMER_ROLE, msg.sender), "unauthorized");

        uint256 cycle = currentCycle();
        amount = _claimable(account);

        require(amount > 0, "no claimable amount");
        lastClaim[account] = cycle;
        emit RevenueClaimed(msg.sender, account, cycle, amount);

        revenueToken.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice View method that returns an amount of revenue that is claimable, given a specific `account`.
     * @param account Address of shareholder.
     * @return amount Amount of revenue that is currently claimable.
     */
    function claimable(address account) external view returns (uint256 amount) {
        amount = _claimable(account);
    }

    /**
     * @notice View method that returns the `cycles` array.
     */
    function getCyclesArray() external view returns (uint256[] memory) {
        return cycles;
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
     * @return amount Amount of `revenueToken` that is currently claimable for `account`.
     */
    function _claimable(address account) internal view returns (uint256 amount) {
        uint256 numCycles = cycles.length;
        uint256 lastCycle = lastClaim[account];
        uint256 i = 1;
        uint256 cycle = cycles[numCycles - i];

        while (i < numCycles && cycle > lastCycle) {
            uint256 currentRevenue = revenue[cycle];

            uint256 votingPowerAtTime = Votes(votingEscrow).getPastVotes(account, cycle);
            uint256 totalPowerAtTime = Votes(votingEscrow).getPastTotalSupply(cycle);

            if (votingPowerAtTime != 0) {
                amount += (currentRevenue * votingPowerAtTime) / totalPowerAtTime;
            }

            cycle = cycles[numCycles - (++i)];
        }
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}