// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./IMarketplace.sol";

interface IPassiveIncomeNFT {
    struct Lock {
        uint256 startTime;
        uint256 endTime;
        uint256 tokenizationCost;
        uint256 multiplier;
        uint256 claimed;
        uint256 maxPayout;
    }

    function locks(uint256 piTokenId) external view returns (Lock memory lock);

    function burn(uint256 tokenId) external returns (uint256 amount);

    function maxLockDuration() external view returns (uint8);

    function claim(uint256 tokenId, uint256 amount) external;

    function canEarnForAmount(uint256 tngblAmount) external view returns (bool);

    function claimableIncome(uint256 tokenId) external view returns (uint256, uint256);

    function mint(
        address minter,
        uint256 tokenizationCost,
        uint8 lockDurationInMonths,
        bool onlyLock,
        bool generateRevenue
    ) external returns (uint256);

    function claimableIncomes(
        uint256[] calldata tokenIds
    ) external view returns (uint256[] memory free, uint256[] memory max);

    function marketplace() external view returns (IMarketplace);
}
