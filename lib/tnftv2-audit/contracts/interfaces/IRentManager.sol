// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface IRentManager {
    struct RentInfo {
        uint256 depositAmount;
        uint256 claimedAmount;
        uint256 claimedAmountTotal;
        uint256 unclaimedAmount;
        uint256 depositTime;
        uint256 endTime;
        address rentToken;
        bool distributionRunning;
    }

    function updateDepositor(address _newDepositor) external;

    function deposit(
        uint256 tokenId,
        address tokenAddress,
        uint256 amount,
        uint256 month,
        uint256 endTime,
        bool skipBackpayment
    ) external;

    function claimableRentForToken(uint256 tokenId) external view returns (uint256);

    function claimRentForToken(uint256 tokenId) external returns (uint256);

    function claimableRentForTokenBatch(
        uint256[] calldata tokenIds
    ) external view returns (uint256[] memory);

    function claimableRentForTokenBatchTotal(
        uint256[] calldata tokenIds
    ) external view returns (uint256 claimable);

    function claimRentForTokenBatch(
        uint256[] calldata tokenIds
    ) external returns (uint256[] memory);

    function TNFT_ADDRESS() external view returns (address);

    function depositor() external view returns (address);

    function notificationDispatcher() external view returns (address);
}

interface IRentManagerExt is IRentManager {
    function rentInfo(uint256) external view returns (RentInfo memory);
}
