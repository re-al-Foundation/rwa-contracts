// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./abstract/FactoryModifiers.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWETH9.sol";
import "./interfaces/IExchange.sol";

import "./exchangeInterfaces/IPearlRouter.sol";

/**
 * @title Exchange
 * @author Veljko Mihailovic
 * @notice This contract is used to exchange Erc20 tokens.
 */
contract ExchangeV2 is IExchange, FactoryModifiers {
    using SafeERC20 for IERC20;

    // ~ State Variables ~

    /// @notice Mapping of concatenated pairs to router address.
    mapping(bytes => address) public routers;

    /// @notice TODO
    mapping(bytes => IRouter.Route[]) public routePaths;

    /// @notice TODO
    mapping(bytes => bool) public simpleSwap;

    /// @notice TODO
    mapping(bytes => bool) public stable;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initialize ~

    /**
     * @notice Initializes the Exchange contract
     * @param _factory Address for the  Factory contract.
     */
    function initialize(address _factory) external initializer {
        __FactoryModifiers_init(_factory);
    }

    // ~ External Funcions ~

    /**
     * @notice This function allows the factory owner to add a new router address to a supported pair.
     * @param tokenInAddress Address of Erc20 token we're exchanging from.
     * @param tokenOutAddress Address of Erc20 token we're exchanging to.
     * @param _router Address of router.
     */
    function addRouterForTokens(
        address tokenInAddress,
        address tokenOutAddress,
        address _router,
        IRouter.Route[] calldata _routes,
        IRouter.Route[] calldata _routesReversed,
        bool _simpleSwap,
        bool _stable
    ) external onlyFactoryOwner {
        require(_routes.length == _routesReversed.length, "mismatch");
        bytes memory tokenized = abi.encodePacked(tokenInAddress, tokenOutAddress);
        bytes memory tokenizedReverse = abi.encodePacked(tokenOutAddress, tokenInAddress);
        // set routes
        routers[tokenized] = _router;
        routers[tokenizedReverse] = _router;
        // set paths if any
        uint256 length = _routes.length;
        for (uint256 i; i < length; ) {
            routePaths[tokenized].push(_routes[i]);
            routePaths[tokenizedReverse].push(_routesReversed[i]);
            unchecked {
                ++i;
            }
        }
        // set if simple swap or with hops
        simpleSwap[tokenized] = _simpleSwap;
        simpleSwap[tokenizedReverse] = _simpleSwap;
        //set if pool is stable or not
        stable[tokenized] = _stable;
        stable[tokenizedReverse] = _stable;
    }

    /**
     * @notice This function exchanges a specified Erc20 token for another Erc20 token.
     * @param tokenIn Address of Erc20 token being token from owner.
     * @param tokenOut Address of Erc20 token being given to the owner.
     * @param amountIn Amount of `tokenIn` to be exchanged.
     * @param minAmountOut The minimum amount expected from `tokenOut`.
     * @return Amount of returned `tokenOut` tokens.
     */
    function exchange(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256) {
        uint256[] memory amounts = new uint256[](2);

        bytes memory tokenized = abi.encodePacked(tokenIn, tokenOut);

        address _router = routers[tokenized];
        require(address(0) != _router, "router 0 ng");
        //take the token
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        //approve the router
        IERC20(tokenIn).approve(_router, amountIn);

        if (simpleSwap[tokenized]) {
            amounts = IRouter(_router).swapExactTokensForTokensSimple(
                amountIn,
                minAmountOut,
                tokenIn,
                tokenOut,
                stable[tokenized],
                msg.sender,
                block.timestamp
            );
        } else {
            amounts = new uint256[](routePaths[tokenized].length);
            amounts = IRouter(_router).swapExactTokensForTokens(
                amountIn,
                minAmountOut,
                routePaths[tokenized],
                msg.sender,
                block.timestamp
            );
        }

        return amounts[amounts.length - 1]; //returns output token amount
    }

    /**
     * @notice This method is used to fetch a quote for an exchange.
     * @param tokenIn Address of Erc20 token being token from owner.
     * @param tokenOut Address of Erc20 token being given to the owner.
     * @param amountIn Amount of `tokenIn` to be exchanged.
     * @return Amount of `tokenOut` tokens for quote.
     */
    function quoteOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256) {
        uint256[] memory amounts = new uint256[](2);

        bytes memory tokenized = abi.encodePacked(tokenIn, tokenOut);
        address _router = routers[tokenized];
        require(address(0) != _router, "router 0 qo");

        if (simpleSwap[tokenized]) {
            (amounts[1], ) = IRouter(_router).getAmountOut(amountIn, tokenIn, tokenOut);
        } else {
            amounts = new uint256[](routePaths[tokenized].length);
            amounts = IRouter(_router).getAmountsOut(amountIn, routePaths[tokenized]);
        }

        return amounts[amounts.length - 1];
    }
}
