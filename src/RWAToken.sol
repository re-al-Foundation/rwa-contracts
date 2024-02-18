// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";

/**
 * @title RWAToken
 * @author @chasebrownn
 * @notice ERC-20 contract for $RWA token. This contract does contain a taxing mechanism on buys / sells / & transfers.
 */
contract RWAToken is UUPSUpgradeable, OwnableUpgradeable, ERC20Upgradeable {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Stores maximum supply.
    uint256 public constant MAX_SUPPLY = 33_333_333 ether;

    /// @notice If true, `account` is excluded from fees (aka whitelisted).
    mapping(address account => bool) public isExcludedFromFees;

    /// @notice If true, `account` is blacklisted from buying, selling, or transferring tokens.
    /// @dev Unless the recipient or sender is whitelisted.
    mapping(address account => bool) public isBlacklisted;

    /// @notice If true, `pair` is a verified pair/pool.
    mapping(address pair => bool) public automatedMarketMakerPairs;

    address public votingEscrowRWA;

    address public royaltyHandler;

    address public lzReceiver;

    /// @notice Total fee taken on buys and sells.
    uint16 public fee;


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
     * @notice This event is emitted when `updateFee` is executed.
     * TODO
     */
    event FeeUpdated(uint256 oldFee, uint256 newFee);


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
     */
    function initialize(
        address _admin
    ) external initializer {
        __ERC20_init("re.al", "RWA");
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[_admin] = true;
        isExcludedFromFees[address(0)] = true;

        fee = 5;
    }


    // -------
    // Methods
    // -------

    /**
     * @notice This method allows a permissioned admin to update the buy/sell fee
     * @param _fee New fee taken on buys and sells.
     */
    function updateFee(uint16 _fee) external onlyOwner {
        require(_fee <= 10, "sum of fees cannot exceed 10%s");
        emit FeeUpdated(fee, _fee);
        fee = _fee;
    }

    /**
     * @notice TODO
     */
    function setRoyaltyHandler(address _royaltyHandler) external onlyOwner {
        if (_royaltyHandler == address(0)) revert ZeroAddress();
        royaltyHandler = _royaltyHandler;
        isExcludedFromFees[_royaltyHandler] = true;
    }

    function setReceiver(address _receiver) external onlyOwner {
        if (_receiver == address(0)) revert ZeroAddress();
        lzReceiver = _receiver;
        isExcludedFromFees[_receiver] = true;
    }

    function setVotingEscrowRWA(address _veRWA) external onlyOwner {
        if (_veRWA == address(0)) revert ZeroAddress();
        votingEscrowRWA = _veRWA;
        isExcludedFromFees[_veRWA] = true;
    }

    /**
     * @notice This method allows a permissioned admin to set a new automated market maker pair.
     * @param pair Pair contract address.
     * @param value If true, `pair` is a verified pair address or pool. Otherwise, false.
     */
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        if (pair == address(0)) revert ZeroAddress();
        _setAutomatedMarketMakerPair(pair, value);
    }

    /**
     * @notice This method allows a permissioned admin to modify whitelisted addresses.
     * @dev Whitelisted addresses are excluded from fees.
     * @param account Address that is (or is not) excluded from fees.
     * @param excluded If true, `account` is excluded from fees. Otherwise, false.
     */
    function excludeFromFees(address account, bool excluded) external onlyOwner {
        isExcludedFromFees[account] = excluded;
        emit ExcludedFromFees(account, excluded);
    }

    /**
     * @notice This method allows a permissioned admin to modify blacklisted addresses.
     * @param account Address that is (or is not) blacklisted.
     * @param blacklisted If true, `account` is blacklisted. Otherwise, false.
     */
    function modifyBlacklist(address account, bool blacklisted) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        isBlacklisted[account] = blacklisted;
        emit BlacklistModified(account, blacklisted);
    }
    
    /**
     * @notice Allows a permissioned address to burn tokens.
     * @param amount Amount of tokens to burn.
     */
    function burn(uint256 amount) public {
        require(msg.sender == votingEscrowRWA || msg.sender == royaltyHandler, "Not authorized");
        _burn(msg.sender, amount);
    }

    // /**
    //  * @notice Allows a permissioned address to burn tokens from an external address (with valid allowance).
    //  * @param who Address to burn tokens from.
    //  * @param amount Amount of tokens to burn.
    //  */
    // function burnFrom(address who, uint256 amount) public override {
    //     require(msg.sender == votingEscrowRWA, "Not authorized");
    //     _burn(who, amount);
    // }

    /**
     * @notice Allows a permissioned address to mint new $RWA tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(uint256 amount) external {
        require(msg.sender == votingEscrowRWA, "Not authorized");
        _mint(msg.sender, amount);
    }

    /**
     * @notice Allows a permissioned address to mint tokens to an external address.
     * @param who Address to mint tokens to.
     * @param amount Amount of tokens to mint.
     */
    function mintFor(address who, uint256 amount) external {
        require(msg.sender == lzReceiver, "Not authorized");
        _mint(who, amount);
    }

    
    // ----------------
    // Internal Methods
    // ----------------

    event Debug(uint256);

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

        if (!excludedAccount) { // if not whitelisted

            if (isBlacklisted[from]) revert Blacklisted(from);
            if (isBlacklisted[to]) revert Blacklisted(to);

            // if transaction is a buy or sell, take fee.
            if(automatedMarketMakerPairs[from] || automatedMarketMakerPairs[to]) {
                uint256 feeAmount;

                feeAmount = (amount * fee) / 100;       
                amount -= feeAmount;

                require(royaltyHandler != address(0), "No royalty handler assigned");
                super._update(from, royaltyHandler, feeAmount);
            }
        }

        super._update(from, to, amount);
        require(totalSupply() <= MAX_SUPPLY, "max. supply exceeded");
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
    function _authorizeUpgrade(address) internal override onlyOwner {}
}