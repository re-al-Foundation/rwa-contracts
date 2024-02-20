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
    address public WETH;
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
     */
    function initialize(
        address _admin,
        address _revDist,
        address _rwaToken,
        address _weth,
        address _router,
        address _quoter
    ) external initializer {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        revDistributor = _revDist;
        rwaToken = IERC20(_rwaToken);
        WETH = _weth;
        swapRouter = ISwapRouter(_router);
        quoter = IQuoterV2(_quoter);

        burnPortion = 2; // 2/5
        revSharePortion = 2; // 2/5
        lpPortion = 1; // 1/5

        poolFee = 100;
    }


    // ----------------
    // External Methods
    // ----------------

    /// @dev Allows address(this) to receive ETH.
    receive() external payable {
        require(msg.sender == address(swapRouter), "RoyaltyHandler: unauthorized ETH sender");
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
     * @notice This method allows a permissioned admin to update the pool fee on the RWA/WETH pool it uses to swap RWA->WETH.
     * @param _fee pool fee.
     */
    function updateFee(uint24 _fee) external onlyOwner {
        require(_fee == 100 || _fee == 500 || _fee == 3000 || _fee == 10000, "RoyaltyHandler: Invalid fee");
        poolFee = _fee;
    }

    /**
     * @notice This method allows a permissioned admin to distribute all $RWA royalties collected in this contract.
     */
    function distributeRoyalties() external {
        uint256 amount = rwaToken.balanceOf(address(this));
        require(amount != 0, "RoyaltyHandler: insufficient balance");
        _handleRoyalties(amount);
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
        _addLiquidity(amountForLp, address(this).balance);

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
            tokenOut: WETH,
            amountIn: tokenAmount,
            fee: poolFee,
            sqrtPriceLimitX96: 0
        });
        (uint256 amountOut,,,) = quoter.quoteExactInputSingle(quoteParams);

        // b. build swap params
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(rwaToken),
            tokenOut: WETH,
            fee: poolFee,
            recipient: address(swapRouter),
            deadline: block.timestamp,
            amountIn: tokenAmount,
            amountOutMinimum: amountOut,
            sqrtPriceLimitX96: 0
        });

        bytes memory swap = 
            abi.encodeWithSignature(
                "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                swapParams.tokenIn,
                swapParams.tokenOut,
                swapParams.fee,
                swapParams.recipient,
                swapParams.deadline,
                swapParams.amountIn,
                swapParams.amountOutMinimum,
                swapParams.sqrtPriceLimitX96
            );

        bytes memory unwrap =
            abi.encodeWithSignature(
                "unwrapWETH9(uint256,address)",
                amountOut,
                address(this)
            );
        
        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = swap;
        multicallData[1] = unwrap;

        // c. swap
        rwaToken.approve(address(swapRouter), tokenAmount);
        (bool success,) = address(swapRouter).call(abi.encodeWithSignature("multicall(bytes[])", multicallData));
        require(success, "RoyaltyHandler: swap failed");
    }

    /**
     * @notice This internal method adds liquidity to the $RWA/ETH pool.
     * @param tokensForLp Desired amount of $RWA tokens to add to pool.
     * @param amountETH Desired amount of ETH to add to pool.
     */
    function _addLiquidity(uint256 tokensForLp, uint256 amountETH) internal {
        // TODO send to Automatic Liquidity Manager
        // Liquidity Box

        // 1. Add liquidity via LiquidBoxManager.deposit
        // 2. Stake LP tokens on GaugeV2ALM
        // 3. Receive Pearl emissions
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}