// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IRWAVotingEscrow {

    /**
     * @notice This method is called by the RealReceiver contract to fulfill the cross-chain migration from 3,3+ to veRWA.
     * @param _receiver The account being minted a new token.
     * @param _lockedBalance Amount of tokens to lock in new lock.
     * @param _duration Duration of new lock in seconds.
     * @return tokenId -> Token identifier minted to `_receiver`.
     */
    function migrate(address _receiver, uint256 _lockedBalance, uint256 _duration) external returns (uint256 tokenId);

    /**
     * @notice This method is called by the RealReceiver contract to fulfill the cross-chain migration of a batch of 3,3+ NFTs to veRWA NFTs.
     * @param _receiver The account being minted a batch of new tokens.
     * @param _lockedBalances Array of amounts of tokens to lock in new locks.
     * @param _durations Array of durations of new locks (in seconds). Indexes correspond with `_lockedBalances`.
     * @return tokenIds -> Token identifiers minted to `_receiver`.
     */
    function migrateBatch(address _receiver, uint256[] memory _lockedBalances, uint256[] memory _durations) external returns (uint256[] memory tokenIds);

}