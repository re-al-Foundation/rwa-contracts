// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../../abstract/AdminAccess.sol";

contract MockRevenueShare is AdminAccess {
    mapping(uint256 => address) tokenIdToClaimer;
    uint256 private itterator;

    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR");
    bytes32 public constant SHARE_MANAGER_ROLE = keccak256("SHARE_MANAGER");

    function updateShare(
        address /*contractAddress*/,
        uint256 /*tokenId*/,
        int256 /*amount*/
    ) external onlyRole(SHARE_MANAGER_ROLE) {
        itterator++;
    }

    function share(bytes memory token) external view returns (int256) {
        return int256(345472);
    }

    function unregisterContract(address /*contractAddress*/) external onlyRole(SHARE_MANAGER_ROLE) {
        itterator++;
    }

    function claimForToken(
        address contractAddress,
        uint256 tokenId
    ) external onlyRole(CLAIMER_ROLE) {
        itterator++;
    }

    function forToken(
        address contractAddress,
        uint256 tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (MockRevenueShare) {
        return MockRevenueShare(this);
    }
}
