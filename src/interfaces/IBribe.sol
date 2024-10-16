// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/**
 * @title IBribe
 * @notice Interface for managing bribes and rewards.
 */
interface IBribe {
  struct Reward {
    uint256 periodFinish;
    uint256 rewardsPerEpoch;
    uint256 lastUpdateTime;
  }
  /**
   * @notice Returns the address of the bribe owner.
   */
  function owner() external view returns (address);

  /**
   * @notice Returns the address of the voter.
   */
  function voter() external view returns (address);

  /**
   * @notice Returns the address of the minter.
   */
  function minter() external view returns (address);

  /**
   * @notice Initializes the gauge with the provided parameters.
   * @param isMainChain bool for main chain
   * @param lzMainChainId The layerzero ChainId of the main chain.
   * @param lzPoolChainId The layerzero ChainId of the pool.
   * @param owner The address of the Owner contract.
   * @param voter The address of the Voter contract.
   * @param bribeFactory The address of the BribeFactory contract.
   * @param _type The bribe contract type
   */
  function initialize(
    bool isMainChain,
    uint16 lzMainChainId,
    uint16 lzPoolChainId,
    address owner,
    address voter,
    address bribeFactory,
    string memory _type
  ) external;

  /**
   * @notice Deposits vote into the bribe for a specified account.
   * @param amount The amount of vote to deposit.
   * @param account The account to deposit for.
   */
  function _deposit(uint256 amount, address account) external;

  /**
   * @notice Withdraws vote from the contract for a specified account.
   * @param amount The amount of vote to withdraw.
   * @param account The account to withdraw from.
   */
  function _withdraw(uint256 amount, address account) external;

  /**
   * @notice whitelists reward token
   * @param token The address of the token to whitelist for bribe reward.
   */
  function addReward(address token) external;

  /**
   * @notice Gets the vote balance of an account at a specific timestamp.
   * @param account The account to check the balance for.
   * @param _timestamp The timestamp at which to check the balance.
   * @return balance vote balance of the account at the specified timestamp.
   */
  function balanceOfAt(
    address account,
    uint256 _timestamp
  ) external view returns (uint256);

  /**
   * @notice Calculates the earned rewards for an account with a specific reward token.
   * @param account The account to calculate rewards for.
   * @param _rewardToken The reward token for which to calculate rewards.
   * @return The earned rewards for the account and reward token.
   */
  function earned(
    address account,
    address _rewardToken
  ) external view returns (uint256);

  /**
   * @notice Gets the timestamp of the first bribe.
   * @return The timestamp of the first bribe.
   */
  function firstBribeTimestamp() external view returns (uint256);

  /**
   * @notice Gets the start of the current epoch.
   * @return The start of the current epoch.
   */
  function getEpochStart() external view returns (uint256);

  /**
   * @notice Gets the start of the next epoch.
   * @return The start of the next epoch.
   */
  function getNextEpochStart() external view returns (uint256);

  /**
   * @notice Gets the rewards for the owner of the contract.
   * @param account The account for which to get rewards.
   * @param tokens The list of reward tokens to get rewards for.
   */
  function getRewardForOwner(address account, address[] memory tokens) external;

  /**
   * @notice Notifies the contract about the amount of rewards to be distributed.
   * @param token The address of the token for which rewards are being distributed.
   * @param amount The amount of rewards to be distributed.
   */
  function notifyRewardAmount(address token, uint256 amount) external;

  /**
   * @notice Uses isRecoverERC20AndUpdateData to decide either recover some ERC20 from the contract and updated given bribe
   *         or just recover some ERC20 from the contract.
   * @dev    Be careful --> if isRecoverERC20AndUpdateData is set to false then getReward() at last epoch will fail because some reward are missing!
   *         Think about setting isRecoverERC20AndUpdateData as true.
   * @param data token(s) and amount(s) to recover.
   * @param isRecoverERC20AndUpdateData indicator to updated given bribe or not while recovering some ERC20 from the contract.
   */
  function emergencyRecoverERC20AndRecoverData(
    bytes calldata data,
    bool isRecoverERC20AndUpdateData
  ) external;

  /**
   * @notice Gets bribe reward data for a specific token at a specific timestamp.
   * @param _token The reward token for which to get reward.
   * @param _timestamp The epoch timestamp
   * @return The reward data.
   */
  function rewardData(
    address _token,
    uint256 _timestamp
  ) external view returns (Reward memory);

  /**
   * @notice Gets the list of whitelisted reward token at a specific index.
   * @param _index The index of the reward token.
   * @return The address of the reward token.
   */
  function rewardTokens(uint256 _index) external view returns (address);

  /**
   * @notice Gets the length of the rewards list.
   * @return The length of the rewards list.
   */
  function rewardsListLength() external view returns (uint256);

  /**
   * @notice Sets the minter address.
   * @param _minter The address of the minter.
   */
  function setMinter(address _minter) external;

  /**
   * @notice Sets the owner address.
   * @param _owner The address of the owner.
   */
  function setOwner(address _owner) external;

  /**
   * @notice Sets the voter address.
   * @param _voter The address of the voter.
   */
  function setVoter(address _voter) external;

  /**
   * @notice Gets the total supply at a specific timestamp.
   * @param _timestamp The timestamp for which to get the total supply.
   * @return The total supply at the specified timestamp.
   */
  function totalSupplyAt(uint256 _timestamp) external view returns (uint256);

  /**
   * @notice Transfers rewards in USTB from the child chain to main chain.
   */
  function transferUSTB() external payable;

  /**
   * @notice Converts a specific reward token to USTB.
   * @dev To avoid misuse, convert data is compared with passed parameters to avoid exploits.
   *      Only callable by the keeper.
   * @param _token The token to convert.
   * @param _amount The amount to convert.
   * @param _target The target address for conversion.
   * @param _data The call data for conversion.
   */
  function convertBribeToken(
    address _token,
    uint256 _amount,
    address _target,
    bytes calldata _data
  ) external;

  function addRewards(address[] memory _rewardsToken) external;

  function notifyCredit(
    uint16 srcChainId,
    address initiator,
    address,
    address token,
    uint256 reward
  ) external;

  function ackReward(uint64 _nonce) external;
}