// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface IMarketplace {
    function afterBurnToken(uint256 tokenId) external;

    function updateTokenOwner(
        uint256 tokenId,
        address from,
        address to
    ) external;
}
