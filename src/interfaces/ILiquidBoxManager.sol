// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidBoxManager {
  /**
   * @notice set pool factory contract address
   * @param factory Address of pearlV3 pool factory
   */
  function setFactory(address factory) external;

  /**
   * @notice get box address using params
   * @param token0 Address of token0 of the pearlV2 pool
   * @param token1 Address of token1 of the pearlV2 pool
   * @param fee Amount of fee of the pearlV2 pool
   * @return box Address of the box
   */
  function getBox(
    address token0,
    address token1,
    uint24 fee
  ) external view returns (address box);

  /**
   * @notice Deposits tokens into the vault, distributing them
   * in proportion to the current holdings.
   * @dev Tokens deposited remain in the vault until the next
   * rebalance and are not utilized for liquidity on Pearl.
   * @param box Box address
   * @param deposit0 Maximum amount of token0 to deposit
   * @param deposit1 Maximum amount of token1 to deposit
   * @param amount0Min Reverts if the resulting amount0 is less than this
   * @param amount1Min Reverts if the resulting amount1 is less than this
   * @return shares Number of shares minted
   */
  function deposit(
    address box,
    uint256 deposit0,
    uint256 deposit1,
    uint256 amount0Min,
    uint256 amount1Min
  ) external returns (uint256 shares);

  /**
   * @notice Withdraws tokens from the vault, proportionally to the vault's holdings.
   * @param box Address of the liquidity box
   *  @param shares Shares burned by the sender
   * @param amount0Min Reverts if the resulting amount0 is less than this
   * @param amount1Min Reverts if the resulting amount1 is less than this
   * @return amount0 Amount of token0 sent to the recipient
   * @return amount1 Amount of token1 sent to the recipient
   */
  function withdraw(
    address box,
    uint256 shares,
    uint256 amount0Min,
    uint256 amount1Min
  ) external returns (uint256 amount0, uint256 amount1);

  /**
   * @notice Updates vault's positions in the Pearl pool.
   * @dev Only one order is places - a base order
   * order must consume all the liquidity in the box
   */
  function rebalance(
    address box,
    int24 baseLower,
    int24 baseUpper,
    uint256 amount0MinBurn,
    uint256 amount1MinBurn,
    uint256 amount0MinMint,
    uint256 amount1MinMint
  ) external;

  /**
   * @notice Updates vault's positions.
   * @dev Pull liquidity out from the pool
   * @param box address of the liquidity box to pull liquidity
   * @param baseLower lower limit of the position
   * @param baseUpper upper limit of the position
   * @param shares quantity of the lp tokens
   * @param amount0Min minimum amount in token0 to be added in the pool
   * @param amount1Min minimum amount in token1 to be added in the pool
   */
  function pullLiquidity(
    address box,
    int24 baseLower,
    int24 baseUpper,
    uint128 shares,
    uint256 amount0Min,
    uint256 amount1Min
  ) external;

  /**
   * @notice Claims collected management fees and transfers them to the specified address.
   * @dev This function can only be called by the owner of the contract.
   * @param box The address to which the fee will be collected.
   * @param to The address to which the collected fees will be transferred.
   * @return claimed0 The amount of collected fees denominated in token0.
   * @return claimed1 The amount of collected fees denominated in token1.
   */
  function claimFees(
    address box,
    address to
  ) external returns (uint256 claimed0, uint256 claimed1);

  /**
   * @notice Claims collected management fees and transfers them to the specified address.
   * @dev This function can only be called by the owner of the contract.
   * @param box The address to which the fee will be collected.
   * @param to The address to which the collected fees will be transferred.
   * @return collectedfees0 The amount of collected fees denominated in token0.
   * @return collectedfees1 The amount of collected fees denominated in token1.
      * @return collectedFeesOnEmission The amount of collected fees on reward emission from gauge.

   */
  function claimManagementFees(
    address box,
    address to
  )
    external
    returns (
      uint256 collectedfees0,
      uint256 collectedfees1,
      uint256 collectedFeesOnEmission
    );

  /**
   * @notice Calculates the amounts of token0, token1 and lqiuidity using
   * shares for a given recipient address of th box.
   * @param box The address of the liquid box
   * @param to The address of the recipient for which the shares are being calculated.
   * @return amount0 The calculated amount of token0 shares for the recipient.
   * @return amount1 The calculated amount of token1 shares for the recipient.
   * @return liquidity The calculated liquidity of shares for the recipient.
   * @dev This function is view-only and does not modify the state of the contract.
   */
  function getSharesAmount(
    address box,
    address to
  ) external view returns (uint256 amount0, uint256 amount1, uint256 liquidity);

  /**
   * @notice get the limit of the liquid box position
   * @param box The address of the liquid box
   * @return baseLower The lower limit of pool position for a given box.
   * @return baseUpper The upper limit of pool position for a given box.
   * @dev This function is view-only and does not modify the state of the contract.
   */
  function getLimits(
    address box
  ) external view returns (int24 baseLower, int24 baseUpper);

  /**
   * @notice Calculates the vault's total holdings of token0 and token1 - in
   * other words, how much of each token the vault would hold if it withdrew
   * all its liquidity from PearlV3.
   * @return total0 The total amount of token0 managed by the box minus the fee.
   * @return total1 The total amount of token1 managed by the box minus the fee.
   * @return pool0 The total amount of token0 deployed in the pool minus management fee.
   * @return pool1 The total amount of token1 deployed in the pool minus management fee.
   * @return liquidity The total liquidity deployed in the pool.
   */
  function getTotalAmounts(
    address box
  )
    external
    view
    returns (
      uint256 total0,
      uint256 total1,
      uint256 pool0,
      uint256 pool1,
      uint128 liquidity
    );

  /**
   * @notice get the limit of the liquid box position
   * @param box The address of the liquid box
   * @param to The address of the recipient for which the shares are being calculated.
   * @return claimable0 The calculated amount of claimable fess in token0.
   * @return claimable1 The calculated amount of claimable fess in token1.
   * @dev This function is view-only and does not modify the state of the contract.
   */
  function getClaimableFees(
    address box,
    address to
  ) external view returns (uint256 claimable0, uint256 claimable1);

  /**
   * @notice Calculates the amounts of token0, token1 and lqiuidity using
   * shares for a given recipient address of th box.
   * @param box The address of the liquid box
   * @param to The address of the recipient for which the shares are being calculated.
   * @return amount The calculated amount of token0 shares for the recipient.
   * @dev This function is view-only and does not modify the state of the contract.
   */
  function balanceOf(
    address box,
    address to
  ) external view returns (uint256 amount);

  /**
   * @notice Returns the management fees for a specific Trident ALM box.
   * @param box Address of the Trident ALM box.
   * @return claimable0 The amount of claimable fees denominated in token0.
   * @return claimable1 The amount of claimable fees denominated in token1.
   * @return emission The amount of fees on reward emission from the gauge.
   */
  function getManagementFees(
    address box
  )
    external
    view
    returns (uint256 claimable0, uint256 claimable1, uint256 emission);
}