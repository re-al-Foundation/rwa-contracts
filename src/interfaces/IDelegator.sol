// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IDelegator {

    /**
     * @notice This method is used to deposit a delegated veRWA NFT into this contract.
     * @dev There should only be 1 NFT deposited during the lifespan of this delegator.
     * @param _tokenId Token identifier of veRWA token.
     */
    function depositDelegatorToken(uint256 _tokenId) external;

    /**
     * @notice This method is used to transfer the `delegatedToken` back to the `creator`.
     */
    function withdrawDelegatedToken() external;
}