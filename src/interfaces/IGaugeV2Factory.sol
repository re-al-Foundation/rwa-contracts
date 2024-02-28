// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGaugeV2Factory {
  /**
   * @notice Create a new master gauge for a specified pool
   * @dev This function can only be called by anyone to create .
   * @param factory The address of the pool for which gauge will be created.
   * @param pool The address of the pool for which gauge will be created.
   * @param rewardToken The address of the staking reward token for the gauge.
   * @param distribution The address of the distribution to update the epoch rewards.
   * @param internalBribe The address of the internalBribe to collect staked lp token fees.
   * @return gauge The address of the master gauge contract.
   * @return gaugeALM The address of the gauge contract for the ALM.
   */
  function createGauge(
    uint16 lzMainChainId,
    uint16 lzPoolChainId,
    address factory,
    address pool,
    address rewardToken,
    address distribution,
    address internalBribe,
    bool isForPair
  ) external returns (address gauge, address gaugeALM);
}