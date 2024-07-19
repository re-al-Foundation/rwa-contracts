// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports\
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { RWAVotingEscrow } from "../governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../governance/VotingEscrowVesting.sol";
import { DelegateFactory } from "../governance/DelegateFactory.sol";
import { Delegator } from "../governance/Delegator.sol";
import { RevenueStreamETH } from "../RevenueStreamETH.sol";

/**
 * @title AutomatedDelegatee
 * @author @chasebrownn
 * @notice This contract takes delegation of a VotingEscrowRWA token and automates the claiming of rewards and transfers
 *         those rewards to a dedicated delegatee address. Ideally, this contract will work in tandum with a gelato task to 
 *         automate the deliverance of rewards to the specified delegatee.
 *
 * Key Features:
 * - This contract must be delegated voting power of a veRWA token.
 * - This contract will query if there are any rewards claimable.
 * - If so, it will claim those rewards and transfer it to a dedicated EOA.
 */
contract AutomatedDelegatee is UUPSUpgradeable, OwnableUpgradeable {
    // ---------------
    // State Variables
    // ---------------

    /// @dev Contract reference for RevenueStreamETH.
    RevenueStreamETH public constant REV_STREAM = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);
    /// @dev Address of delegatee rewards receiver.
    address public delegatee;
    /// @dev This uint tracks total amount of rewards claimed.
    uint256 public totalClaimed;


    // ---------------
    // Events & Errors
    // ---------------

    event RewardsClaimed(uint256 amount, address indexed receiver);
    
    error ETHSendFailed();
    error InvalidAmount(uint256 amount);
    error ZeroAddressException();


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
     * @notice This initializes RWAToken.
     * @param _admin Initial default admin address.
     * @param _delegatee Address where rewards will be sent.
     */
    function initialize(
        address _admin,
        address _delegatee
    ) external initializer {
        if (_admin == address(0)) revert ZeroAddressException();
        if (_delegatee == address(0)) revert ZeroAddressException();

        __Ownable_init(_admin);
        delegatee = _delegatee;
    }


    // ----------------
    // External Methods
    // ----------------

    /// @dev Allows this contract to receive Ether.
    receive() external payable {}

    /**
     * @notice TODO
     */
    function claimRewards(uint256 minClaimable) external returns (uint256 claimed) {
        uint256 amountClaimable = claimable();
        // check amount claimable
        if (minClaimable > amountClaimable) revert InvalidAmount(amountClaimable);
        // claim
        claimed = REV_STREAM.claimETH();
        // increment totalClaimed
        totalClaimed += claimed;
        // send ETH to delegatee
        _sendETH(delegatee, claimed);
    }

    /**
     * @notice TODO
     */
    function claimRewardsIncrement(uint256 numIndexes) external returns (uint256 claimed) {
        // claim in increments
        claimed = REV_STREAM.claimETHIncrement(numIndexes);
        // increment totalClaimed
        totalClaimed += claimed;
        // send ETH to delegatee
        _sendETH(delegatee, claimed);
    }

    /**
     * @notice This permissioned external method is used to withdraw ETH from this contract.
     * @param amount Amount of ETH to withdraw.
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        if (amount > address(this).balance || amount == 0) revert InvalidAmount(amount);
        _sendETH(owner(), amount);
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @notice Returns amount of ETH that is claimable.
     */
    function claimable() public view returns (uint256) {
        return REV_STREAM.claimable(address(this));
    }
    
    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice TODO
     */
    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value:amount}("");
        if (!success) revert ETHSendFailed();
    }

    /**
     * @notice Overrides UUPSUpgradeable.
     * @dev Restricts ability to upgrade contract to owner.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}