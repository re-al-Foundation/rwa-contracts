// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title An interface for a contract that is capable of deploying Pearl V2 Pools
/// @notice A contract that constructs a pool must implement this to pass arguments to the pool
/// @dev This is used to avoid having constructor arguments in the pool contract, which results in the init code hash
/// of the pool being constant allowing the CREATE2 address of the pool to be cheaply computed on-chain
interface IPearlV2PoolFactory {
    /// @notice Emitted when the owner of the factory is changed
    /// @param oldOwner The owner before the owner was changed
    /// @param newOwner The owner after the owner was changed
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    /// @notice Emitted when a pool is created
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param pool The address of the created pool
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );

    /// @notice Emitted when a new fee amount is enabled for pool creation via the factory
    /// @param fee The enabled fee, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks for pools created with the given fee
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

    /// @notice Returns the current owner of the factory
    /// @dev Can be changed by the current owner via setOwner
    /// @return The address of the factory owner
    function owner() external view returns (address);

    /// @notice Returns the address of the pool implementation
    /// @return The address of the pool implementation
    function poolImplementation() external view returns (address);

    /// @notice Returns the address of the gauge for the pool
    /// @dev only rebase proxy can skim the surplus rebasing tokens
    /// to be distributed as the bribe to the voters.
    /// @return The address of the USTB rebase proxy controller
    function rebaseProxy() external view returns (address);

    /// @notice Returns the address of the pool manager
    /// @dev poolManager has rights to create the pool and set the inital
    /// price of the pool.
    /// @return The address of the pool manager of the factory.
    function poolManager() external view returns (address);

    /// @notice Returns the address of the gauge manager
    /// @dev gaugeManager has rights to set the gauge address in the pool
    /// @return The address of the gauge manager of the factory.
    function gaugeManager() external view returns (address);

    /// @notice Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled
    /// @dev A fee amount can never be removed, so this value should be hard coded or cached in the calling context
    /// @param fee The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee
    /// @return The tick spacing
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);

    /// @notice Creates a pool for the given two tokens and fee
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param fee The desired fee for the pool
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. tickSpacing is retrieved
    /// from the fee. The call will revert if the pool already exists, the fee is invalid, or the token arguments
    /// are invalid.
    /// @return pool The address of the newly created pool
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);

    /// @notice Updates the owner of the factory
    /// @dev Must be called by the current owner
    /// @param _owner The new owner of the factory
    function setOwner(address _owner) external;

    /// @notice Enables a fee amount with the given tickSpacing
    /// @dev Fee amounts may never be removed once enabled
    /// @param fee The fee amount to enable, denominated in hundredths of a bip (i.e. 1e-6)
    /// @param tickSpacing The spacing between ticks to be enforced for all pools created with the given fee amount
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;

    /// @notice Get the parameters to be used in constructing the pool, set transiently during pool creation.
    /// @dev Called by the pool constructor to fetch the parameters of the pool
    /// Returns factory The factory address
    /// Returns token0 The first token of the pool by address sort order
    /// Returns token1 The second token of the pool by address sort order
    /// Returns fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// Returns tickSpacing The minimum number of ticks between initialized ticks
    function parameters()
        external
        view
        returns (address factory, address token0, address token1, uint24 fee, int24 tickSpacing);

    /// @notice Sets the gauge address for the pool
    /// @dev Called by the pool manager or gauge manager to
    /// set gauge address for the pool
    /// @param pool address of the pool
    /// @param gauge address of the gauge
    function setPoolGauge(address pool, address gauge) external;

    /// @notice set pool manager address
    /// @param _manager address of the pool manager
    function setPoolManager(address _manager) external;

    /// @notice set gauge manager address
    /// @param _manager address of the gauge manager
    function setGaugeManager(address _manager) external;

    /// @notice set USTB rebase proxy address
    /// @param _rebaseProxy address of the ustb rebase controller
    function setRebaseProxy(address _rebaseProxy) external;

    /// @notice Sets the initial price for the pool
    /// @dev Called by the pool manager to set the initial price of the pool.
    /// Price is represented as a sqrt(amountToken1/amountToken0) Q64.96 value
    /// @param pool address of the pool
    /// @param sqrtPriceX96 the initial sqrt price of the pool as a Q64.96
    function initializePoolPrice(address pool, uint160 sqrtPriceX96) external;

    /// @notice Get the total number of the pools
    /// @return size total number of the generated pools
    function allPairsLength() external view returns (uint256 size);

    /// @notice Get the pool address at the specified index
    /// @param index array index
    /// @return pair address of the pool at the specified index
    function allPairs(uint256 index) external view returns (address pair);
}