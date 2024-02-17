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
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";

/**
 * @title RoyaltyHandler
 * @author @chasebrownn
 * @notice TODO
 */
contract RoyaltyHandler is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------

    IUniswapV2Router02 public uniswapV2Router;
    
    /// @notice Stores the address of RWAToken contract.
    IERC20 public rwaToken;

    /// @notice Stores the address to the veRWA RevenueDistributor.
    address public revDistributor;

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
        address _router
    ) external initializer {
        _transferOwnership(_admin);

        revDistributor = _revDist;
        rwaToken = IERC20(_rwaToken);
        uniswapV2Router = IUniswapV2Router02(_router);

        burnPortion = 2; // 2%
        revSharePortion = 2; // 2%
        lpPortion = 1; // 1%
    }


    // -------
    // Methods
    // -------

    /// @dev Allows address(this) to receive ETH.
    receive() external payable {} // TODO

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
     * @notice This method allows a permissioned admin to distribute all $RWA royalties collected in this contract.
     */
    function distributeRoyalties() external {
        uint256 amount = rwaToken.balanceOf(address(this));
        require(amount != 0, "insufficient balance");
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
        require(success, "burn unsuccessful");

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
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(rwaToken);
        path[1] = uniswapV2Router.WETH();

        rwaToken.approve(address(uniswapV2Router), tokenAmount);
        uint256[] memory amounts = uniswapV2Router.getAmountsOut(tokenAmount, path);

        // make the swap
        uniswapV2Router.swapExactTokensForETH(
            tokenAmount,
            amounts[1],
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @notice This internal method adds liquidity to the $RWA/ETH pool.
     * @param tokensForLp Desired amount of $RWA tokens to add to pool.
     * @param amountETH Desired amount of ETH to add to pool.
     */
    function _addLiquidity(uint256 tokensForLp, uint256 amountETH) internal {
        rwaToken.approve(address(uniswapV2Router), tokensForLp);
        // add liquidity to LP
        uniswapV2Router.addLiquidityETH{value: amountETH}(
            address(rwaToken),
            tokensForLp,
            0, // since ratio will be unknown, assign 0 RWA minimum
            0, // since ratio will be unknown, assign 0 ETH minimum
            owner(),
            block.timestamp
        );
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}