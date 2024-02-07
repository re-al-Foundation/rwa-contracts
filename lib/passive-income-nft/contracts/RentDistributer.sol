// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IOps.sol";
import "./interfaces/RevenueShare.sol";

contract RentDistributor is AccessControl {
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR");

    using SafeERC20 for IERC20;

    IERC20 public immutable revenueToken;

    RevenueShare public rentShareContract;

    uint256 public dailyAmount;
    uint256 public nextDistribution;

    constructor(address tokenContractAddress) {
        revenueToken = IERC20(tokenContractAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        nextDistribution = block.timestamp;
    }

    function setRevenueShareContract(address contractAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rentShareContract = RevenueShare(contractAddress);
    }

    function deposit(uint256 amount) external onlyRole(DEPOSITOR_ROLE) {
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balance = revenueToken.balanceOf(address(this));
        dailyAmount = balance / 31;
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        canExec = block.timestamp >= nextDistribution;
        execPayload = abi.encodeWithSelector(this.distribute.selector);
    }

    function distribute() external onlyRole(DISTRIBUTOR_ROLE) {
        require(
            address(rentShareContract) != address(0),
            "contract address not set"
        );
        require(dailyAmount > 0, "no scheduled payments");
        require(
            revenueToken.balanceOf(address(this)) >= dailyAmount,
            "no funds left"
        );
        require(block.timestamp >= nextDistribution, "too soon");
        revenueToken.approve(address(rentShareContract), dailyAmount);
        rentShareContract.deposit(dailyAmount);
        nextDistribution += 24 hours;
    }

    function withdraw(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revenueToken.safeTransfer(msg.sender, amount);
    }
}
