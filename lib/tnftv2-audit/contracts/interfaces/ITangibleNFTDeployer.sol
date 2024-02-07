// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./ITangibleNFT.sol";

/// @title ITangibleNFTDeployer interface defines the interface of the TangibleNFTDeployer.
interface ITangibleNFTDeployer {
    /// @dev Will deploy a new TangibleNFT contract and return the TangibleNFT reference.
    function deployTnft(
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        bool _symbolInUri,
        uint256 _tnftType
    ) external returns (ITangibleNFT);
}
