// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20BurnableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";

/**
 * @title RWAToken
 * @author @chasebrownn
 * @notice ERC-20 contract for $RWA token. This contract does contain a taxing mechanism on buys / sells / & transfers.
 */
contract RWAToken is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ERC20BurnableUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Role identifier for ability to burn $RWA tokens.
    bytes32 public constant BURNER_ROLE = keccak256("BURNER");

    /// @notice Role identifier for ability to mint $RWA tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    /// @notice Stores maximum supply.
    uint256 public constant MAX_SUPPLY = 33_333_333 ether;

    /// @notice Amount of accumulated $RWA royalties needed to distribute royalties.
    uint256 public swapTokensAtAmount;

    /// @notice If true, `account` is excluded from fees (aka whitelisted).
    mapping(address account => bool) public isExcludedFromFees;

    /// @notice If true, `account` is blacklisted from buying, selling, or transferring tokens.
    /// @dev Unless the recipient or sender is whitelisted.
    mapping(address account => bool) public isBlacklisted;

    /// @notice If true, `pair` is a verified pair/pool.
    mapping(address pair => bool) public automatedMarketMakerPairs;

    /// @notice Stores the contract reference to the local Uniswap V2 Router contract.
    IUniswapV2Router02 public uniswapV2Router;
    
    /// @notice Stores the address to the RWA/WETH Uniswap pair.
    address public uniswapV2Pair;

    /// @notice Stores the address to the veRWA RevenueDistributor.
    address public revDistributor;

    /// @notice Stores the address of the Uniswap pair tokens recipient. These tokens are created when
    ///         we add liquidity to `uniswapV2Pair`. By default is set to initial admin in initializer.
    address public pairTokensRecipient;

    /// @notice Fee taken for burning $RWA.
    uint16 public burnFee;

    /// @notice Fee taken for veRWA revenue share.
    uint16 public revShareFee;

    /// @notice Fee taken for adding liquidity.
    uint16 public lpFee;

    /// @notice Total fee taken. `burnFee` + `revShareFee` + `lpFee`.
    uint16 public totalFees;

    /// @notice Used to prevent re-entrancy during royalty distribution.
    bool private swapping;


    // ---------
    // Modifiers
    // ---------

    /**
     * @notice This modifier is used to lock a method to avoid re-entrancy.
     */
    modifier lockSwap() {
        swapping = true;
        _;
        swapping = false;
    }


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when `excludeFromFees` is executed.
     * @param account Address that was (or was not) excluded from fees.
     * @param isExcluded If true, `account` is excluded from fees. Otherwise, false.
     */
    event ExcludedFromFees(address indexed account, bool isExcluded);

    /**
     * @notice This event is emitted when `modifyBlacklist` is executed.
     * @param account Address that was (or was not) blacklisted.
     * @param blacklisted If true, `account` is blacklisted. Otherwise, false.
     */
    event BlacklistModified(address indexed account, bool blacklisted);

    /**
     * @notice This event is emitted when `automatedMarketMakerPairs` is modified.
     * @param pair Pair contract address.
     * @param value If true, `pair` is a verified pair address or pool. Otherwise, false.
     */
    event SetAutomatedMarketMakerPair(address indexed pair, bool value);

    /**
     * @notice This event is emitted when `updateFees` is executed.
     * @param totalFee New total fee taken out of 100%.
     * @param burnFee New burn fee.
     * @param revShareFee New fee taken for veRWA revenue share.
     * @param lpFee New fee taken for adding liquidity.
     */
    event FeesUpdated(uint256 totalFee, uint8 burnFee, uint8 revShareFee, uint8 lpFee);

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


    // ------
    // Errors
    // ------

    /**
     * @notice This error is emitted when an account that is blacklisted tries to buy, sell, or transfer RWA.
     * @param account Blacklisted account that attempted transaction.
     */
    error Blacklisted(address account);

    /**
     * @notice This error is emitted from an invalid address(0) input.
     */
    error ZeroAddress();


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
     * @param _router Local Uniswap v2 router address.
     * @param _revDist RevenueDistributor contract address.
     */
    function initialize(
        address _admin,
        address _router,
        address _revDist
    ) external initializer {
        __ERC20_init("re.al", "RWA");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        pairTokensRecipient = _admin;

        revDistributor = _revDist;

        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[_admin] = true;
        isExcludedFromFees[_revDist] = true;
        isExcludedFromFees[address(0)] = true;

        if (_router != address(0)) {
            uniswapV2Router = IUniswapV2Router02(_router);
            //uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
            //_setAutomatedMarketMakerPair(uniswapV2Pair, true);
        }

        swapTokensAtAmount = 50 ether; // TODO: Verify

        burnFee = 2; // 2%
        revShareFee = 2; // 2%
        lpFee = 1; // 1%
        totalFees = burnFee + revShareFee + lpFee;
    }


    // -------
    // Methods
    // -------

    /// @dev Allows address(this) to receive ETH.
    receive() external payable {}

    /**
     * @notice This method allows a permissioned admin to update the fees
     * @dev The value contains 
     * @param _burnFee New burn fee.
     * @param _revShareFee New fee taken for veRWA revenue share.
     * @param _lpFee New fee taken for adding liquidity.
     */
    function updateFees(uint8 _burnFee, uint8 _revShareFee, uint8 _lpFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        totalFees = _burnFee + _revShareFee + _lpFee;

        require(totalFees <= 10, "sum of fees cannot exceed 10%s");
        
        burnFee = _burnFee;
        revShareFee = _revShareFee;
        lpFee = _lpFee;

        emit FeesUpdated(totalFees, _burnFee, _revShareFee, _lpFee);
    }

    /**
     * @notice This method allows a permissioned admin to distribute all $RWA royalties collected in this contract.
     */
    function distributeRoyalties() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!swapping, "royalty dist in progress");

        uint256 amount = balanceOf(address(this));
        require(amount != 0, "insufficient balance");

        _handleRoyalties(amount);
    }

    /**
     * @notice This method allows a permissioned admin to update the `uniswapV2Pair` var.
     * @dev Used in the event the pool has to be created post deployment.
     * @param pair Pair Address -> Should be RWA/WETH.
     */
    function setUniswapV2Pair(address pair) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uniswapV2Pair = pair;
        _setAutomatedMarketMakerPair(pair, true);
    }

    /**
     * @notice This method allows a permissioned admin to update the `uniswapV2Router` var.
     * @param router Uniswap V2 Router address.
     */
    function setUniswapV2Router(address router) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (router == address(0)) revert ZeroAddress();
        uniswapV2Router = IUniswapV2Router02(router);
    }

    /**
     * @notice This method allows a permissioned admin to set a new automated market maker pair.
     * @param pair Pair contract address.
     * @param value If true, `pair` is a verified pair address or pool. Otherwise, false.
     */
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (pair == address(0)) revert ZeroAddress();
        _setAutomatedMarketMakerPair(pair, value);
    }

    /**
     * @notice This method allows a permissioned admin to update the `revDistributor` variable.
     * @param revDist New RevenueDistributor address.
     */
    function setRevenueDistributor(address revDist) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (revDist == address(0)) revert ZeroAddress();
        revDistributor = revDist;
    }

    /**
     * @notice This method allows a permissioned admin to update the `pairTokensRecipient` variable.
     * @param recipient New recipient of liquidity pair tokens.
     */
    function setPairTokensRecipient(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        pairTokensRecipient = recipient;
    }

    /**
     * @notice This method allows a permissioned admin to modify whitelisted addresses.
     * @dev Whitelisted addresses are excluded from fees.
     * @param account Address that is (or is not) excluded from fees.
     * @param excluded If true, `account` is excluded from fees. Otherwise, false.
     */
    function excludeFromFees(address account, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isExcludedFromFees[account] = excluded;
        emit ExcludedFromFees(account, excluded);
    }

    /**
     * @notice This method allows a permissioned admin to modify blacklisted addresses.
     * @param account Address that is (or is not) blacklisted.
     * @param blacklisted If true, `account` is blacklisted. Otherwise, false.
     */
    function modifyBlacklist(address account, bool blacklisted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        isBlacklisted[account] = blacklisted;
        emit BlacklistModified(account, blacklisted);
    }

    /**
     * @notice This method allows a permissioned admin to set the new royalty balance threshold to trigger distribution.
     * @param swapAmount New amount of tokens to accumulate before distributing.
     */
    function setSwapTokensAtAmount(uint256 swapAmount) onlyRole(DEFAULT_ADMIN_ROLE) external {
        swapTokensAtAmount = swapAmount * (10 ** decimals());
    }
    
    /**
     * @notice Allows a permissioned address to burn tokens.
     * @param amount Amount of tokens to burn.
     */
    function burn(uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burn(amount);
    }

    /**
     * @notice Allows a permissioned address to burn tokens from an external address (with valid allowance).
     * @param who Address to burn tokens from.
     * @param amount Amount of tokens to burn.
     */
    function burnFrom(address who, uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burnFrom(who, amount);
    }

    /**
     * @notice Allows a permissioned address to mint new $RWA tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(msg.sender, amount);
    }

    /**
     * @notice Allows a permissioned address to mint tokens to an external address.
     * @param who Address to mint tokens to.
     * @param amount Amount of tokens to mint.
     */
    function mintFor(address who, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(who, amount);
    }

    /**
     * @notice This method returns the amount of RWA tokens inside the contract, most likely accrued from taxes.
     * @return amount -> Amount of RWA in the contract
     * @return enoughToSwap -> If true `amount` is greater than or equal to `swapTokensAtAmount`.
     * @dev If `enoughToSwap` is true, the next sell or transfer will trigger a distribution of royalties.
     */
    function getRWABalanceOfContract() public view returns (uint256 amount, bool enoughToSwap) {
        amount = balanceOf(address(this));
        enoughToSwap = amount >= swapTokensAtAmount;
    }

    
    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Transfers an `amount` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`.
     * @dev This overrides `_update` from ERC20Upgradeable.`
     *      Unless `from` or `to` is excluded, there will be a tax on the transfer.
     * @param from Address balance decreasing.
     * @param to Address balance increasing.
     * @param amount Amount of tokens being transferred from `from` to `to`.
     */
    function _update(address from, address to, uint256 amount) internal override {

        // note: if automatedMarketMakerPairs[from] == true -> BUY
        // note: if automatedMarketMakerPairs[to] == true   -> SELL

        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];

        if (!excludedAccount) { //If not whitelisted

            if (isBlacklisted[from]) revert Blacklisted(from);
            if (isBlacklisted[to]) revert Blacklisted(to);

            if (!automatedMarketMakerPairs[from]) { // if NOT a buy, distribute royalties and make swaps
            
                // take contract balance of royalty tokens
                (uint256 contractTokenBalance, bool canSwap) = getRWABalanceOfContract();
                
                if (!swapping && canSwap) {
                    _handleRoyalties(contractTokenBalance);
                }
            }
        }

        bool takeFee = !swapping && !excludedAccount;

        // if `takeFee` == true & the transaction is a buy or sell, take a fee.
        if(takeFee && (automatedMarketMakerPairs[from] || automatedMarketMakerPairs[to])) {
            uint256 fees;

            fees = (amount * totalFees) / 100;        
            amount -= fees;

            super._update(from, address(this), fees);
        }

        super._update(from, to, amount);
        require(totalSupply() <= MAX_SUPPLY, "max. supply exceeded");
    }

    /**
     * @notice This internal method is used to distribute the royalties collected by this contract.
     * @param amount Amount to distribute.
     */
    function _handleRoyalties(uint256 amount) internal lockSwap {
        uint256 burnPortion = (amount * burnFee) / totalFees; // 2/5 default
        uint256 revSharePortion = (amount * revShareFee) / totalFees; // 2/5 default
        uint256 lpPortion = amount - burnPortion - revSharePortion; // 1/5 default

        _burn(address(this), burnPortion);
        super._update(address(this), revDistributor, revSharePortion);

        uint256 tokensForEth = lpPortion / 2;
        lpPortion -= tokensForEth;

        _swapTokensForETH(tokensForEth);
        _addLiquidity(lpPortion, address(this).balance);

        emit RoyaltiesDistributed(amount, revSharePortion, burnPortion, lpPortion);
    }

    /**
     * @notice This internal method takes `tokenAmount` of tokens and swaps it for ETH.
     * @param tokenAmount Amount of $RWA tokens being swapped/sold for ETH.
     */
    function _swapTokensForETH(uint256 tokenAmount) internal {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);
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
        _approve(address(this), address(uniswapV2Router), tokensForLp);
        // add liquidity to LP
        uniswapV2Router.addLiquidityETH{value: amountETH}(
            address(this),
            tokensForLp,
            0, // since ratio will be unknown, assign 0 RWA minimum
            0, // since ratio will be unknown, assign 0 ETH minimum
            pairTokensRecipient,
            block.timestamp + 100
        );
    }

    /**
     * @notice This internal method updates the `automatedMarketMakerPairs` mapping.
     * @param pair Pair contract address.
     * @param value If true, address is set as an AMM pair. Otherwise, false.
     */
    function _setAutomatedMarketMakerPair(address pair, bool value) internal {
        require(automatedMarketMakerPairs[pair] != value, "Already set");

        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}