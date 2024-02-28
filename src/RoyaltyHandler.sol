// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// oz upgradeable imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { ISwapRouter } from "./interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "./interfaces/IQuoterV2.sol";
import { ILiquidBoxManager } from "./interfaces/ILiquidBoxManager.sol";
import { ILiquidBox } from "./interfaces/ILiquidBox.sol";
import { IGaugeV2ALM } from "./interfaces/IGaugeV2ALM.sol";

/**
 * @title RoyaltyHandler
 * @author @chasebrownn
 * @notice This contract accrues royalties from RWAToken swap taxes and when triggered, will distribute royalties
 *         to burn, RevenueDistributor, and to ALM.
 */
contract RoyaltyHandler is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------
    
    /// @notice Stores the address of RWAToken contract.
    IERC20 public rwaToken;
    /// @notice Stores the address of the SwapRouter contract.
    ISwapRouter public swapRouter;
    /// @notice Stores the address of the QuoterV2 contract.
    IQuoterV2 public quoter;
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


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when `updateFees` is executed.
     * @param burnPortion New burn fee.
     * @param revSharePortion New fee taken for veRWA revenue share.
     * @param lpPortion New fee taken for adding liquidity.
     */
    event DistributionUpdated(uint8 burnPortion, uint8 revSharePortion, uint8 lpPortion);

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
     * @param _quoter QuoterV2 contract address.
     * @param _boxManager LiquidBoxManager contract address.
     */
    function initialize(
        address _admin,
        address _revDist,
        address _rwaToken,
        address _weth,
        address _router,
        address _quoter,
        address _boxManager
    ) external initializer {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        revDistributor = _revDist;
        rwaToken = IERC20(_rwaToken);
        WETH = IERC20(_weth);
        swapRouter = ISwapRouter(_router);
        quoter = IQuoterV2(_quoter);
        boxManager = ILiquidBoxManager(_boxManager);

        burnPortion = 2; // 2/5
        revSharePortion = 2; // 2/5
        lpPortion = 1; // 1/5

        poolFee = 100;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows a permissioned admin to distribute all $RWA royalties collected in this contract.
     */
    function distributeRoyalties() external {
        uint256 amount = rwaToken.balanceOf(address(this));
        require(amount != 0, "RoyaltyHandler: insufficient balance");
        _handleRoyalties(amount);
    }

    /**
     * @notice This method allows a permissioned admin to update the fees
     * @dev The value contains 
     * @param _burnPortion New burn fee.
     * @param _revSharePortion New fee taken for veRWA revenue share.
     * @param _lpPortion New fee taken for adding liquidity.
     */
    function updateDistribution(uint8 _burnPortion, uint8 _revSharePortion, uint8 _lpPortion) external onlyOwner {   
        uint256 totalFee = _burnPortion + _burnPortion + _lpPortion;

        burnPortion = _burnPortion;
        revSharePortion = _burnPortion;
        lpPortion = _lpPortion;

        emit DistributionUpdated(_burnPortion, _revSharePortion, _lpPortion);
    }

    /**
     * @notice This method is used to update the `box` variable.
     */
    function setALMBox(address _box) external onlyOwner {
        box = _box;
    }
    
    /**
     * @notice This method is used to update the `boxManager` variable.
     */
    function setALMBoxManager(address _boxManager) external onlyOwner {
        boxManager = ILiquidBoxManager(_boxManager);
    }

    /**
     * @notice This method is used to update the `gaugeV2ALM` variable.
     */
    function setGaugeV2ALM(address _gaugeV2) external onlyOwner {
        gaugeV2ALM = IGaugeV2ALM(_gaugeV2);
    }

    /**
     * @notice This method is used to update the `pearl` variable.
     */
    function setPearl(address _pearl) external onlyOwner {
        pearl = IERC20(_pearl);
    }

    /**
     * @notice This method is used to update the `swapRouter` variable.
     */
    function setSwapRouter(address _swapRouter) external onlyOwner {
        swapRouter = ISwapRouter(_swapRouter);
    }

    /**
     * @notice This method is used to update the `quoter` variable.
     */
    function setQuoter(address _quoter) external onlyOwner {
        quoter = IQuoterV2(_quoter);
    }

    /**
     * @notice This method allows a permissioned admin to update the pool fee on the RWA/WETH pool it uses to swap RWA->WETH.
     * @param _fee pool fee.
     */
    function updateFee(uint24 _fee) external onlyOwner {
        require(_fee == 100 || _fee == 500 || _fee == 3000 || _fee == 10000, "RoyaltyHandler: Invalid fee");
        poolFee = _fee;
    }

    /**
     * @notice This method allows a permissioned admin to withdraw Pearl from this contract.
     */
    function withdrawPearl(uint256 amount) external onlyOwner {
        uint256 bal = pearl.balanceOf(address(this));
        require(bal != 0 && bal >= amount, "RoyaltyHandler: Insufficient ERC20");
        pearl.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice This method allows a permissioned admin to harvest Pearl rewards from staked LP tokens.
     */
    function harvestPearlRewards() external onlyOwner returns (uint256) {
        uint256 preBal = IERC20(pearl).balanceOf(address(this));
        gaugeV2ALM.collectReward();
        return IERC20(pearl).balanceOf(address(this)) - preBal;
    }

    /**
     * @notice This view method returns the amount of Pearl rewards that are harvestable.
     */
    function earnedPearlRewards() external view returns (uint256) {
        return gaugeV2ALM.earnedReward(address(this));
    }

    
    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice This internal method is used to distribute the royalties collected by this contract.
     * @param amount Amount to distribute.
     */
    function _handleRoyalties(uint256 amount) internal {
        uint256 totalFee = burnPortion + revSharePortion + lpPortion;

        uint256 amountToBurn = (amount * burnPortion) / totalFee; // 2/5 default
        uint256 amountForRevShare = (amount * revSharePortion) / totalFee; // 2/5 default
        uint256 amountForLp = amount - amountToBurn - amountForRevShare; // 1/5 default

        // burn
        (bool success,) = address(rwaToken).call(abi.encodeWithSignature("burn(uint256)", amountToBurn));
        require(success, "RoyaltyHandler: burn unsuccessful");

        // rev share
        rwaToken.safeTransfer(revDistributor, amountForRevShare);

        // lp
        uint256 tokensForEth = amountForLp / 2;
        amountForLp -= tokensForEth;

        _swapTokensForETH(tokensForEth);
        _addLiquidity(amountForLp, WETH.balanceOf(address(this)));

        emit RoyaltiesDistributed(amount, amountForRevShare, amountToBurn, amountForLp);
    }

    /**
     * @notice This internal method takes `tokenAmount` of tokens and swaps it for ETH.
     * @param tokenAmount Amount of $RWA tokens being swapped/sold for ETH.
     */
    function _swapTokensForETH(uint256 tokenAmount) internal {

        // a. Get quote
        IQuoterV2.QuoteExactInputSingleParams memory quoteParams = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: address(rwaToken),
            tokenOut: address(WETH),
            amountIn: tokenAmount,
            fee: poolFee,
            sqrtPriceLimitX96: 0
        });
        (uint256 amountOut,,,) = quoter.quoteExactInputSingle(quoteParams);

        // b. build swap params
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(rwaToken),
            tokenOut: address(WETH),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tokenAmount,
            amountOutMinimum: amountOut,
            sqrtPriceLimitX96: 0
        });

        // c. swap
        rwaToken.approve(address(swapRouter), tokenAmount);

        uint256 preBal = WETH.balanceOf(address(this));
        swapRouter.exactInputSingle(swapParams);

        require(preBal + amountOut == WETH.balanceOf(address(this)), "RoyaltyHandler: Insufficient WETH received");
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