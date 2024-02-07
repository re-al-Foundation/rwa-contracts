// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../TangibleRevenueShare.sol";

contract RevenueShareCleanup is Ownable {
    TangibleRevenueShare private immutable revenueShare;

    constructor(address revenueShareAddress) {
        revenueShare = TangibleRevenueShare(revenueShareAddress);
    }

    function invalidate(
        address contractAddress,
        uint256 from,
        uint256 to
    ) external onlyOwner {
        for (uint256 tokenId = from; tokenId <= to; tokenId++) {
            bytes memory token = abi.encodePacked(contractAddress, tokenId);
            int256 share = revenueShare.share(token);
            if (share != 0) {
                revenueShare.updateShare(contractAddress, tokenId, -share);
            }
        }
    }
}
