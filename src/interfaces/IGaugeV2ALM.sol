// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IGaugeV2ALM
 * @dev Interface for the GaugeV2ALM contract, managing reward distribution, liquidity rebalancing, and fee claiming.
 */
interface IGaugeV2ALM {
  /**
   * @notice Initializes the GaugeV2ALM contract with initial parameters.
   * @param _rewardToken Address of the reward token.
   * @param _almBox Address of the associated ALM box.
   * @param _gaugeCL Address of the CL gauge.
   * @param _lBoxManager Address of the LBox manager.
   */
  function initialize(
    address _rewardToken,
    address _almBox,
    address _gaugeCL,
    address _lBoxManager
  ) external;

  /**
   * @notice Sets the ALM box address.
   * @param almBox Address of the ALM box.
   */
  function setBox(address almBox) external;

  /**
   * @notice Creates a new gauge and returns its address.
   * @param rewardToken Address of the reward token.
   * @param almBox Address of the associated ALM box.
   * @param gaugeCL Address of the CL gauge.
   * @param lBoxManager Address of the LBox manager.
   * @return Address of the newly created gauge.
   */
  function createGauge(
    address rewardToken,
    address almBox,
    address gaugeCL,
    address lBoxManager
  ) external returns (address);

  /**
   * @notice Claims fees from the gauge.
   * @return claimed0 The amount of claimed fees denominated in token0.
   * @return claimed1 The amount of claimed fees denominated in token1.
   */
  function claimFees() external returns (uint256 claimed0, uint256 claimed1);

  /**
   * @notice Returns the address for collecting rewards.
   * @return Address for collecting rewards.
   */
  function collectReward() external view returns (address);

  /**
   * @notice Rebalances gauge liquidity.
   * @param newtickLower New lower tick limit.
   * @param newtickUpper New upper tick limit.
   * @param burnLiquidity Amount of liquidity to burn.
   * @param mintLiquidity Amount of liquidity to mint.
   */
  function rebalanceGaugeLiquidity(
    int24 newtickLower,
    int24 newtickUpper,
    uint128 burnLiquidity,
    uint128 mintLiquidity
  ) external;

  /**
   * @notice Pulls gauge liquidity.
   */
  function pullGaugeLiquidity() external;

  /**
   * @notice Claims collected management fees and transfers them to the specified address.
   * @param to The address to which the collected fees will be transferred.
   * @return collectedfees The amount of collected fees denominated in reward tokens.
   */
  function claimManagementFees(
    address to
  ) external returns (uint256 collectedfees);

  /**
   * @notice Returns the balance of a user.
   * @param account The address of the account.
   * @return The balance of the user.
   */
  function balanceOf(address account) external view returns (uint256);

  /**
   * @notice Returns the total supply held.
   * @return The total supply.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @notice Returns the earned rewards for a specific account.
   * @param account The address of the account.
   * @return The amount of earned rewards.
   */
  function earnedReward(address account) external view returns (uint256);

  /**
   * @notice Returns the earned fees for the staked LP token.
   * @return amount0 The amount of earned fees denominated in token0.
   * @return amount1 The amount of earned fees denominated in token1.
   */
  function earnedFees()
    external
    view
    returns (uint256 amount0, uint256 amount1);

  /**
   * @notice Returns the total earned management fees on emissions.
   * @return The total amount of earned management fees.
   */
  function earnedManagentFees() external view returns (uint256);

  /**
   * @notice Returns the amounts and liquidity for the staked LP token by an account.
   * @param account The address of the account.
   * @return The staked amounts and liquidity.
   */
  function getStakedAmounts(
    address account
  ) external view returns (uint256, uint256, uint256);

  /**
   * @notice Returns the address of the associated ALM box.
   * @return Address of the ALM box.
   */
  function getBox() external view returns (address);

  function deposit(uint256 amount) external;
}