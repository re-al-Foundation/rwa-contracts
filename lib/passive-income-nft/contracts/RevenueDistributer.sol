// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/RevenueShare.sol";
import "./interfaces/IOps.sol";

contract RevenueDistributor is AccessControl {
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR");

    using SafeERC20 for IERC20;

    IERC20 public immutable revenueToken;

    RevenueShare public revenueShareContract;

    uint256 public nextDistribution;
    bytes32 public taskId;

    constructor(address tokenContractAddress) {
        revenueToken = IERC20(tokenContractAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        nextDistribution = (block.timestamp / 1 days + 1) * 1 days;
    }

    function setRevenueShareContract(address contractAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        revenueShareContract = RevenueShare(contractAddress);
    }

    function start(address ops) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (taskId != bytes32(0)) {
            stop(ops);
        }
        taskId = IOps(ops).createTask(
            address(this),
            this.distribute.selector,
            address(this),
            abi.encodeWithSelector(this.checker.selector)
        );
    }

    function stop(address ops) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(taskId != bytes32(0), "task is not running");
        IOps(ops).cancelTask(taskId);
        taskId = bytes32(0);
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
            address(revenueShareContract) != address(0),
            "contract address not set"
        );
        uint256 amount = revenueToken.balanceOf(address(this));
        require(amount > 0, "no funds available");
        nextDistribution += 24 hours;
        revenueToken.approve(address(revenueShareContract), amount);
        revenueShareContract.deposit(amount);
    }
}
