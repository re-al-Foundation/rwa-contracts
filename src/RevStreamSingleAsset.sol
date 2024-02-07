// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// oz upgradeable imports
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

// local imports
import { RevenueDistributor } from "./RevenueDistributor.sol";
import { IRevenueStream } from "./interfaces/IRevenueStream.sol";
import { IRevenueStreamETH } from "./interfaces/IRevenueStreamETH.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";

/**
 * @title RevStreamSingleAsset
 * @author @chasebrownn
 * @notice This contract allows an eligible veRWA stakeholder to claim their revenue shares as a single ERC-20 asset.
 *         If an account has any claimable revenue from any existing RevenueStream or RevenueStreamETH contracts,
 *         this contract will claim and swap the assets to a single asset before transferring to the account's wallet.
 */
contract RevStreamSingleAsset is AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------

    /// @notice Role identifier for restricing access to claiming mechanisms.
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");
    /// @notice RevenueDistributor contract reference.
    RevenueDistributor public revenueDistributor;
    /// @notice UniswapV2Router contract reference.
    IUniswapV2Router02 public uniswapV2Router;
    /// @notice ERC-20 token chosen for single asset claims.
    /// @dev ALl outstanding rev share in streams will be converted to this token.
    IERC20 public singleToken;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when revenue is claimed by an eligible shareholder.
     * @param claimer EOA that claimed revenue as single token.
     * @param amount Amount of `singleToken` claimed.
     */
    event RevenueClaimedAsSingleToken(address indexed claimer, uint256 amount);


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
     * @notice Initializes RevStreamSingleAsset
     * @param _revDist Contract address for RevenueDistributor.
     * @param _uniV2Router Contract address for UniV2Router.
     * @param _singleAssetToken Contract address for desried ERC-20 token for `singleToken`.
     * @param _admin Admin address.
     */
    function initialize(
        address _revDist,
        address _uniV2Router,
        address _singleAssetToken,
        address _admin
    ) external initializer {
        uniswapV2Router = IUniswapV2Router02(_uniV2Router);
        revenueDistributor = RevenueDistributor(payable(_revDist));
        singleToken = IERC20(_singleAssetToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows address(this) to receive ETH.
     */
    receive() external payable {}

    /**
     * @notice This method allows an eligible stakeholder to claim all their revenue share as a single asset.
     * @dev This method will claim all claimable revenue from all RevenueStream contracts and swap it to `singleToken`.
     *      There MUST exist a pool for each pair singleToken/RevStream.revenueToken.
     * @param account Stakeholder address with claimable revenue.
     * @return totalClaimed -> Total amount of `singleToken` claimed.
     */
    function claimAsSingleAsset(address account) external returns (uint256 totalClaimed) {
        require(account == msg.sender || hasRole(CLAIMER_ROLE, msg.sender), "unauthorized");

        address[] memory streams = revenueDistributor.getRevenueTokensArray();

        for (uint256 i; i < streams.length;) {
            address revStream = address(revenueDistributor.revStreamETH());

            IERC20 token = IRevenueStream(revStream).revenueToken();
            uint256 claimed = IRevenueStream(revStream).claim(account);

            if (claimed != 0) {
                if (address(token) != address(singleToken)) {
                    uint256 amountOut = _swapTokensForSingleAsset(address(token), claimed);
                    totalClaimed += amountOut;
                }
                else {
                    totalClaimed += claimed;
                }
            }

            unchecked {
                ++i;
            }
        }

        address revStreamETH = address(revenueDistributor.revStreamETH());
        if (revStreamETH != address(0)) {
            uint256 claimed = IRevenueStreamETH(revStreamETH).claimETH(account);

            if (claimed != 0) {
                uint256 amountOut = _swapETHForSingleAsset(claimed);
                totalClaimed += amountOut;
            }
        }

        singleToken.transfer(account, totalClaimed);
    }

    /**
     * @notice This view method returns the amount of ERC-20 `singleToken` is claimable by an eligible account.
     * @param account Stakeholder address with claimable revenue.
     * @return totalClaimable -> Total amount of `singleToken` that is claimable for `account`.
     */
    function claimableAsSingleAsset(address account) external view returns (uint256 totalClaimable) {

        address[] memory streams = revenueDistributor.getRevenueTokensArray();

        for (uint256 i; i < streams.length;) {
            address revStream = address(revenueDistributor.revStreamETH());

            uint256 claimable = IRevenueStream(revStream).claimable(account);
            IERC20 token = IRevenueStream(revStream).revenueToken();

            if (claimable != 0) {
                if (address(token) != address(singleToken)) {
                    uint256 quote = _getQuote(address(token), claimable);
                    totalClaimable += quote;
                }
                else {
                    totalClaimable += claimable;
                }
            }

            unchecked {
                ++i;
            }
        }

        address revStreamETH = address(revenueDistributor.revStreamETH());
        if (revStreamETH != address(0)) {
            uint256 claimable = IRevenueStreamETH(revStreamETH).claimable(account);

            if (claimable != 0) {
                uint256 quote = _getQuote(uniswapV2Router.WETH(), claimable);
                totalClaimable += quote;
            }
        }
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice This method will take an `amount` of ERC-20 `tokenIn` and swap it for `singleToken`.
     * @param tokenIn ERC-20 token address of token being swapped to `singleToken`.
     * @param amount Amount of tokens being swapped.
     * @return amountOut -> amount of `singleToken` that came out of swap.
     */
    function _swapTokensForSingleAsset(address tokenIn, uint256 amount) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);

        path[0] = tokenIn;
        path[1] = address(singleToken);

        IERC20(tokenIn).approve(address(uniswapV2Router), amount);

        uint256[] memory amounts = 
            uniswapV2Router.swapExactTokensForTokens(
                amount,
                _getQuote(path[0], amount),
                path,
                address(this),
                block.timestamp + 100
            );

        return amounts[1];
    }

    /**
     * @notice This method will take an `amount` of ETH and swap it for `singleToken`.
     * @param amount Amount of ETH being swapped.
     * @return amountOut -> amount of `singleToken` that came out of swap.
     */
    function _swapETHForSingleAsset(uint256 amount) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);

        path[0] = uniswapV2Router.WETH();
        path[1] = address(singleToken);

        uint256[] memory amounts = 
            uniswapV2Router.swapExactETHForTokens{value: amount}(
                _getQuote(path[0], amount),
                path,
                address(this),
                block.timestamp + 100
            );

        return amounts[1];
    }

    /**
     * @notice This view method returns a quoted amount of `singleToken` if an `amount` of `tokenIn` was swapped.
     * @dev Does not result in a change of state. Only quoted tokens. No swap occurs.
     * @param tokenIn ERC-20 token being quoted for `singleToken`.
     * @param amount Amount of `tokenIn`.
     * @return quote -> Amount of `singleToken` quoted.
     */
    function _getQuote(address tokenIn, uint256 amount) internal view returns (uint256 quote) {
        address[] memory path = new address[](2);

        path[0] = tokenIn;
        path[1] = address(singleToken);

        uint256[] memory amounts = IUniswapV2Router02(uniswapV2Router).getAmountsOut(amount, path);
        return amounts[1];
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}