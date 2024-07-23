// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { RevenueStreamETH } from "../RevenueStreamETH.sol";

/**
 * @title AutomatedDelegatee
 * @author @chasebrownn
 * @notice This contract takes delegation of a VotingEscrowRWA token and automates the claiming of rewards and transfers
 * those rewards to a dedicated delegatee address. Ideally, this contract will work in tandum with a gelato task to 
 * automate the deliverance of rewards to the specified delegatee.
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
     * @notice This external method is used to claim any claimable rewards from the Revenue Stream contract
     * on behalf of the delegatee.
     * @dev This method will revert if the amount claimable is not greater than `minClaimable`. This is used to
     * save gas on an automated method. I.e. we don't want this method being executed if the amount of claimable
     * revenue is less than the gas it would cost to execute the claim.
     * Once the rewards are claimed, it will be sent directly to the delegatee address.
     * If an automation tool is being used to automate the claiming of rewards to the delegatee, this is the method
     * you want to automate. And ideally, you should simulate the tx before executing to avoid wasting gas on a
     * reverted call. Gelato tasks are a great solution to simulate and automate in a single tool.
     *
     * @param minClaimable Minimum amount that must be claimable in order to execute this method.
     * @return claimed Amount of ETH claimed.
     */
    function claimRewards(uint256 minClaimable) external returns (uint256 claimed) {
        uint256 amountClaimable = claimable();
        // check amount claimable
        if (minClaimable > amountClaimable) revert InvalidAmount(amountClaimable);
        // claim
        claimed = REV_STREAM.claimETH();
        emit RewardsClaimed(claimed, delegatee);
        // increment totalClaimed
        totalClaimed += claimed;
        // send ETH to delegatee
        _sendETH(delegatee, claimed);
    }

    /**
     * @notice This external method is used to claim any claimable rewards from the Revenue Stream contract
     * on behalf of the delegatee. However, it claimes in increments to prevent clogs.
     * @dev This method differs from `claimRewards` in that it will claim in increments. When revenue is
     * distributed to the Revenue Stream contract for claiming it creates an index in an array. It uses a
     * rolling window model to track claimable revenue. In the event there are too many indexes to iterate
     * in 1 transaction, you can perform the claim in smaller iterations to eventually claim all claimable ETH.
     *
     * @param numIndexes Number of indexes to claim.
     * @return claimed Amount of ETH claimed.
     */
    function claimRewardsIncrement(uint256 numIndexes) external returns (uint256 claimed) {
        // claim in increments
        claimed = REV_STREAM.claimETHIncrement(numIndexes);
        emit RewardsClaimed(claimed, delegatee);
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

    /**
     * @notice This permissioned external method is used to update the `delegatee` state variable.
     * @param newDelegatee New delegatee address.
     */
    function updateDelegatee(address newDelegatee) external onlyOwner {
        if (newDelegatee == address(0)) revert ZeroAddressException();
        delegatee = newDelegatee;
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @notice Returns amount of ETH that is claimable.
     */
    function claimable() public view returns (uint256 amount) {
        (amount,,,,) = REV_STREAM.claimable(address(this));
    }
    

    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice This internal method sends ETH using `.call` to a specified address.
     * @param to Where we're sending ETH.
     * @param amount Amount of ETH being sent.
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