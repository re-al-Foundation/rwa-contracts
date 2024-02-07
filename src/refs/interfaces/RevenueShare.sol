// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface RevenueShare {
    function claimableForToken(address contractAddress, uint256 tokenId)
        external
        view
        returns (uint256);

    function claimableForTokens(
        address[] memory contractAddresses,
        uint256[] memory tokenIds
    ) external view returns (uint256[] memory);

    function deposit(uint256 amount) external;

    function updateShare(
        address contractAddress,
        uint256 tokenId,
        int256 amount
    ) external;

    function unregisterContract(address contractAddress) external;
}