// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// oz upgradeable imports
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { ISwapRouter } from "./interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "./interfaces/IQuoterV2.sol";
import { ILiquidBoxManager } from "./interfaces/ILiquidBoxManager.sol";
import { ILiquidBox } from "./interfaces/ILiquidBox.sol";
import { IGaugeV2ALM } from "./interfaces/IGaugeV2ALM.sol";
import { IRWAToken } from "./interfaces/IRWAToken.sol";
import { ITNGBLV3Oracle } from "./interfaces/ITNGBLV3Oracle.sol";

/**
 * @title RoyaltyHandler
 * @author @chasebrownn
 * @notice This contract accrues royalties from RWAToken swap taxes and when triggered, will distribute royalties
 *         to burn, RevenueDistributor, and to ALM.
 */
contract RoyaltyHandler is UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------
    
    /// @notice Stores the address of RWAToken contract.
    IERC20 public rwaToken;
    /// @notice Stores the address of the SwapRouter contract.
    ISwapRouter public swapRouter;
    /// @notice Stores the address of the local WETH token contract.
    IERC20 public WETH;
    /// @notice Stores the address to the veRWA RevenueDistributor.
    address public revDistributor;
    /// @notice Fee of the RWA/WETH pool this contract uses for swapping/liquidity.
    uint24 public poolFee;
    /// @notice Fee taken for burning $RWA.
    uint16 public burnPortion;
    /// @notice Fee taken for veRWA revenue share.
    uint16 public revSharePortion;
    /// @notice Fee taken for adding liquidity.
    uint16 public lpPortion;
    /// @notice Stores contract reference of LiquidBoxManager contract.
    ILiquidBoxManager public boxManager;
    /// @notice Stores address of ERC20 ALM LP tokens.
    address public box;
    /// @notice Stores contract reference to GaugeV2ALM for staking `box` tokens.
    IGaugeV2ALM public gaugeV2ALM;
    /// @notice Stores contract reverence for ERC-20 token PEARL.
    IERC20 public pearl;
    /// @notice Stores address of distributor in the occasion it isn't equal to owner.
    address public distributor;
    /// @notice Stores contract reference to TNGBLV3Oracle.
    ITNGBLV3Oracle public oracle;
    /// @notice Stores percentage deviation aka tolerated slippage for calculating minOut.
    uint256 public percentageDeviation;
    /// @notice Observe look-up used for oracle quoting.
    uint32 public secondsAgo;

    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when `_handleRoyalties` is executed.
     * @dev `sentToRevDist` + `burned` + `addedToLiq` will not equal `totalAmount`. Delta was sold for ETH to
     *      add to liquidity.
     * @param totalAmount Total RWA used.
     * @param sentToRevDist Amount RWA sent to RevenueDistributor.
     * @param burned Amount RWA burned.
     * @param addedToLiq Amount of RWA added to liquidity.
     */
    event RoyaltiesDistributed(uint256 totalAmount, uint256 sentToRevDist, uint256 burned, uint256 addedToLiq);

    /**
     * @notice This event is emitted when `updateFees` is executed.
     * @param burnPortion New burn fee.
     * @param revSharePortion New fee taken for veRWA revenue share.
     * @param lpPortion New fee taken for adding liquidity.
     */
    event DistributionUpdated(uint8 burnPortion, uint8 revSharePortion, uint8 lpPortion);

    /**
     * @notice This event is emitted when a new `percentageDeviation` is set.
     * @param newPercentageDeviation New value stored in `percentageDeviation`.
     */
    event PercentageDeviationSet(uint256 newPercentageDeviation);

    /**
     * @notice This event is emitted when a new `secondsAgo` is set.
     * @param newSecondsAgo New value stored in `secondsAgo`.
     */
    event SecondsAgoSet(uint32 newSecondsAgo);

    /**
     * @notice This event is emitted when a new `distributor` is set.
     * @param newDistributor New value stored in `distributor`.
     */
    event DistributorSet(address indexed newDistributor);

    /**
     * @notice This event is emitted when a new `oracle` is set.
     * @param newOracle New value stored in `oracle`.
     */
    event OracleSet(address indexed newOracle);

    /**
     * @notice This event is emitted when a new `box` is set.
     * @param newALMBox New value stored in `box`.
     */
    event ALMBoxSet(address indexed newALMBox);

    /**
     * @notice This event is emitted when a new `boxManager` is set.
     * @param newBoxManager New value stored in `boxManager`.
     */
    event BoxManagerSet(address indexed newBoxManager);

    /**
     * @notice This event is emitted when a new `gaugeV2ALM` is set.
     * @param newGaugeV2ALM New value stored in `gaugeV2ALM`.
     */
    event GaugeV2ALMSet(address indexed newGaugeV2ALM);

    /**
     * @notice This event is emitted when a new `pearl` is set.
     * @param newPearlAddress New value stored in `pearl`.
     */
    event PearlAddressSet(address indexed newPearlAddress);

    /**
     * @notice This event is emitted when a new `swapRouter` is set.
     * @param newSwapRouter New value stored in `swapRouter`.
     */
    event SwapRouterSet(address indexed newSwapRouter);

    /**
     * @notice This event is emitted when a new `poolFee` is set.
     * @param newPoolFee New value stored in `poolFee`.
     */
    event PoolFeeSet(uint24 newPoolFee);

    /**
     * @notice This event is emitted when assets are withdrawn from this contract.
     * @param token Address of asset being withdrawn. If == address(0), ETH was withdrawn.
     * @param amount Amount of asset withdrawn.
     */
    event FundsWithdrawn(address token, uint256 amount);


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice This initializes RWAToken.
     * @param _admin Initial default admin address.
     * @param _revDist RevenueDistributor contract address.
     * @param _rwaToken RWAToken contract address.
     * @param _weth WETH contract address.
     * @param _router SwapRouter contract address.
     * @param _boxManager LiquidBoxManager contract address.
     * @param _oracle TngblV3Oracle contract address.
     */
    function initialize(
        address _admin,
        address _revDist,
        address _rwaToken,
        address _weth,
        address _router,
        address _boxManager,
        address _oracle
    ) external initializer {
        require(_admin != address(0));
        require(_revDist != address(0));
        require(_rwaToken != address(0));
        require(_weth != address(0));

        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        revDistributor = _revDist;
        rwaToken = IERC20(_rwaToken);
        WETH = IERC20(_weth);
        swapRouter = ISwapRouter(_router);
        boxManager = ILiquidBoxManager(_boxManager);
        oracle = ITNGBLV3Oracle(_oracle);

        burnPortion = 2; // 2/5
        revSharePortion = 2; // 2/5
        lpPortion = 1; // 1/5

        poolFee = 3000;
        secondsAgo = 300;
        percentageDeviation = 200;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method distributes all $RWA royalties collected in this contract.
     */
    function distributeRoyalties() external {
        uint256 amount = rwaToken.balanceOf(address(this));
        require(amount != 0, "RoyaltyHandler: insufficient balance");

        (uint256 amountToBurn, uint256 amountForRevShare, uint256 amountForLp, uint256 tokensForEth) 
            = getRoyaltyDistributions(amount);

        emit RoyaltiesDistributed(amount, amountForRevShare, amountToBurn, amountForLp);

        // burn
        if (amountToBurn != 0) IRWAToken(address(rwaToken)).burn(amountToBurn);

        // rev share
        if (amountForRevShare != 0) rwaToken.safeTransfer(revDistributor, amountForRevShare);

        // lp
        if (amountForLp != 0) {
            _swapTokensForETH(tokensForEth, _getQuote(tokensForEth));
            _addLiquidity(amountForLp, WETH.balanceOf(address(this)));
        }
    }

    /**
     * @notice This method allows a permissioned admin to distribute all $RWA royalties collected in this contract,
     *         but also allows an argument to specify the minimum WETH out from the tokensForEth swap. 
     * @param amountToDistribute amount of RWA to distribute. 
     * @param minOut Minimum amount of WETH expected when making the swap from RWA to WETH prior to depositing this pair into the ALM.
     */
    function distributeRoyaltiesMinOut(uint256 amountToDistribute, uint256 minOut) external {
        require(msg.sender == owner() || msg.sender == distributor, "RoyaltyHandler: NA");

        uint256 amount = amountToDistribute;
        require(rwaToken.balanceOf(address(this)) >= amount, "RoyaltyHandler: insufficient balance");
        
        (uint256 amountToBurn, uint256 amountForRevShare, uint256 amountForLp, uint256 tokensForEth) 
            = getRoyaltyDistributions(amount);

        emit RoyaltiesDistributed(amount, amountForRevShare, amountToBurn, amountForLp);

        // burn
        if (amountToBurn != 0) IRWAToken(address(rwaToken)).burn(amountToBurn);

        // rev share
        if (amountForRevShare != 0) rwaToken.safeTransfer(revDistributor, amountForRevShare);

        // lp
        if (amountForLp != 0) {
            _swapTokensForETH(tokensForEth, minOut);
            _addLiquidity(amountForLp, WETH.balanceOf(address(this)));
        }
    }

    /**
     * @notice This permissioned external method is used to withdraw ETH from this contract.
     * @param amount Amount of ETH to withdraw.
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount && amount != 0, "RoyaltyHandler: Invalid amount");
        emit FundsWithdrawn(address(0), amount);
        (bool success,) = owner().call{value:amount}("");
        require(success, "RoyaltyHandler: ETH Withdraw failed");
    }

    /**
     * @notice This permissioned external method is used to withdraw ERC20 tokens from this contract.
     * @param token Contract address of ERC20 token that's being withdrawn.
     * @param amount Amount of ERC20 tokens to withdraw.
     */
    function withdrawERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "RoyaltyHandler: token cannot be address 0");
        require(IERC20(token).balanceOf(address(this)) >= amount && amount != 0, "RoyaltyHandler: Invalid amount");
        emit FundsWithdrawn(token, amount);
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @notice This method allows a permissioned admin to update the fees
     * @dev The value contains 
     * @param _burnPortion New burn fee.
     * @param _revSharePortion New fee taken for veRWA revenue share.
     * @param _lpPortion New fee taken for adding liquidity.
     */
    function updateDistribution(uint8 _burnPortion, uint8 _revSharePortion, uint8 _lpPortion) external onlyOwner {
        emit DistributionUpdated(_burnPortion, _revSharePortion, _lpPortion);
        burnPortion = _burnPortion;
        revSharePortion = _revSharePortion;
        lpPortion = _lpPortion;
    }

    /**
     * @notice Allows owner to update tolerated slippage when fetching quotes from oracle
     * @param _percentageDeviation New percentage deviation.
     */
    function setPercentageDeviation(uint256 _percentageDeviation) external onlyOwner {
        require(_percentageDeviation <= oracle.POOL_FEE_01(), "RoyaltyHandler: Too high");
        emit PercentageDeviationSet(_percentageDeviation);
        percentageDeviation = _percentageDeviation;
    }

    /**
     * @notice Allows owner to update `secondsAgo` variable.
     */
    function setSecondsAgo(uint32 _secondsAgo) external onlyOwner {
        emit SecondsAgoSet(_secondsAgo);
        secondsAgo = _secondsAgo;
    }

    /**
     * @notice Allows owner to assign distributor role to another address.
     */
    function updateDistributor(address _distributor) external onlyOwner {
        emit DistributorSet(_distributor);
        distributor = _distributor;
    }

    /**
     * @notice Allows owner to update `oracle` state variable.
     */
    function updateOracle(address _oracle) external onlyOwner {
        emit OracleSet(_oracle);
        oracle = ITNGBLV3Oracle(_oracle);
    }

    /**
     * @notice This method is used to update the `box` variable.
     */
    function setALMBox(address _box) external onlyOwner {
        emit ALMBoxSet(_box);
        box = _box;
    }
    
    /**
     * @notice This method is used to update the `boxManager` variable.
     */
    function setALMBoxManager(address _boxManager) external onlyOwner {
        emit BoxManagerSet(_boxManager);
        boxManager = ILiquidBoxManager(_boxManager);
    }

    /**
     * @notice This method is used to update the `gaugeV2ALM` variable.
     */
    function setGaugeV2ALM(address _gaugeV2) external onlyOwner {
        emit GaugeV2ALMSet(_gaugeV2);
        gaugeV2ALM = IGaugeV2ALM(_gaugeV2);
    }

    /**
     * @notice This method is used to update the `pearl` variable.
     */
    function setPearl(address _pearl) external onlyOwner {
        emit PearlAddressSet(_pearl);
        pearl = IERC20(_pearl);
    }

    /**
     * @notice This method is used to update the `swapRouter` variable.
     */
    function setSwapRouter(address _swapRouter) external onlyOwner {
        emit SwapRouterSet(_swapRouter);
        swapRouter = ISwapRouter(_swapRouter);
    }

    /**
     * @notice This method allows a permissioned admin to update the pool fee on the RWA/WETH pool it uses to swap RWA->WETH.
     * @param _fee pool fee.
     */
    function updateFee(uint24 _fee) external onlyOwner {
        require(
            _fee == oracle.POOL_FEE_001() ||
            _fee == oracle.POOL_FEE_005() ||
            _fee == oracle.POOL_FEE_03() ||
            _fee == oracle.POOL_FEE_01() ||
            _fee == oracle.POOL_FEE_1(),
            "RoyaltyHandler: Invalid fee"
        );
        emit PoolFeeSet(_fee);
        poolFee = _fee;
    }

    /**
     * @notice This method allows a permissioned admin to withdraw Pearl from this contract.
     */
    function withdrawPearl(uint256 amount) external onlyOwner {
        uint256 bal = pearl.balanceOf(address(this));
        require(amount != 0 && bal >= amount, "RoyaltyHandler: Insufficient ERC20");
        pearl.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice This method allows a permissioned admin to harvest Pearl rewards from staked LP tokens.
     */
    function harvestPearlRewards() external onlyOwner returns (uint256) {
        uint256 preBal = IERC20(pearl).balanceOf(address(this));
        gaugeV2ALM.claimFees();
        return IERC20(pearl).balanceOf(address(this)) - preBal;
    }

    /**
     * @notice This view method returns the amount of Pearl rewards that are harvestable.
     */
    function earnedPearlRewards() external view returns (uint256) {
        return gaugeV2ALM.earnedReward(address(this));
    }

    // --------------
    // Public Methods
    // --------------

    /**
     * @notice This view method returns the different allocations of `rwaToken` royalties when distributeRoyalties 
     *         is executed with a specified `amount` of RWA.
     * @param amount Amount of RWA royalties to distribute.
     * @return amountToBurn Amount of RWA being burned.
     * @return amountForRevShare Amount of RWA being allocated to veRWA holders.
     * @return amountForLp Amount of RWA being allocated to the Liquidity Manager.
     * @return tokensForEth Amount of RWA being swapped for WETH.
     * @dev amountToBurn + amountForRevShare + amountForLp + tokensForEth == amount
     */
    function getRoyaltyDistributions(uint256 amount) public view returns (
        uint256 amountToBurn, 
        uint256 amountForRevShare, 
        uint256 amountForLp, 
        uint256 tokensForEth
    ) {
        uint256 totalFee = burnPortion + revSharePortion + lpPortion;

        amountToBurn = (amount * burnPortion) / totalFee; // 2/5 default
        amountForRevShare = (amount * revSharePortion) / totalFee; // 2/5 default
        amountForLp = (amount * lpPortion) / totalFee; // 1/5 default

        tokensForEth = amountForLp / 2;
        amountForLp -= tokensForEth;
    }

    
    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice This internal method is used to fetch minimum amount quotes for swaps
     */
    function _getQuote(uint256 amountIn) internal view returns (uint256 amountOut) {
        amountIn = amountIn - ((amountIn * (poolFee + percentageDeviation)) / oracle.POOL_FEE_100());

        amountOut = oracle.consultWithFee(
            address(rwaToken),
            uint128(amountIn),
            address(WETH),
            secondsAgo,
            poolFee
        );
    }

    /**
     * @notice This internal method takes `amountIn` of tokens and swaps it for ETH.
     * @param amountIn Amount of $RWA tokens being swapped/sold for ETH.
     */
    function _swapTokensForETH(uint256 amountIn, uint256 minOut) internal {

        // build swap params
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(rwaToken),
            tokenOut: address(WETH),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });
        uint256 preBal = WETH.balanceOf(address(this));

        // swap
        rwaToken.approve(address(swapRouter), amountIn);
        swapRouter.exactInputSingle(swapParams);

        require(WETH.balanceOf(address(this)) > preBal, "RoyaltyHandler: Insufficient WETH received");
    }

    /**
     * @notice This internal method adds liquidity to the $RWA/WETH pool via an ALM.
     * @dev amount0Min and amount1Min arguments are set to 0 to ensure the liquidity goes through to the ALM.
     *      The amount added to the pool is minimal so front running isn't a worry.
     * @param amountRWA Desired amount of $RWA tokens to add to pool.
     * @param amountWETH Desired amount of WETH to add to pool.
     */
    function _addLiquidity(uint256 amountRWA, uint256 amountWETH) internal {
        // Add liquidity via LiquidBoxManager.deposit
        IERC20(address(rwaToken)).approve(address(boxManager), amountRWA);
        IERC20(address(WETH)).approve(address(boxManager), amountWETH);

        (uint256 amount0, uint256 amount1) = address(ILiquidBox(box).token0()) == address(rwaToken)
            ? (amountRWA, amountWETH)
            : (amountWETH, amountRWA);

        uint256 shares = boxManager.deposit(
            box,
            amount0,
            amount1,
            0, // amount0Min
            0  // amount1Min
        );
        require(shares != 0, "RoyaltyHandler: Insufficient LP Tokens");
        _depositLPTokens(shares);
    }

    function _depositLPTokens(uint256 amount) internal {
        uint256 preBal = IERC20(box).balanceOf(address(this));

        // Stake LP tokens on GaugeV2ALM
        IERC20(box).approve(address(gaugeV2ALM), amount);
        gaugeV2ALM.deposit(amount);

        require(preBal - amount == IERC20(box).balanceOf(address(this)), "RoyaltyHandler: Failed to deposit shares");
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}