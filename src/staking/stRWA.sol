// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// tangible imports
import { LayerZeroRebaseTokenUpgradeable } from "@tangible-foundation-contracts/tokens/LayerZeroRebaseTokenUpgradeable.sol";
import { CrossChainToken } from "@tangible-foundation-contracts/tokens/CrossChainToken.sol";

// local imports
import { TokenSilo } from "./TokenSilo.sol";
import { CommonValidations } from "../libraries/CommonValidations.sol";

/**
 * @title stRWA
 * @author chasebrownn
 * @notice This token is a cross-chain rebasing token. This token can only be minted in exchange for $RWA tokens.
 * Once minted, the $RWA tokens will be locked into a veRWA position to begin accruing revenue. The revenue
 * will be claimed and used to rebase; Distributing revenue amongst $stRWA holders.
 */
contract stRWA is UUPSUpgradeable, LayerZeroRebaseTokenUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using CommonValidations for *;

    // ---------------
    // State Variables
    // --------------- 

    /// @dev Address of token being "wrapped".
    address public immutable asset;
    /// @dev Stores contract reference to the TokenSilo.
    TokenSilo public tokenSilo;
    /// @dev Stores address of rebaseIndexManager. Only this address can call `rebase()`.
    address public rebaseIndexManager;


    // ---------------
    // Events & Errors
    // --------------- 

    event Deposit(address msgSender, address receiver, uint256 amountReceived, uint256 minted);
    event Redeem(address msgSender, address receiver, address owner, uint256 tokenId, uint256 assets, uint256 burned);
    event TokenSiloUpdated(address);
    event RebaseIndexManager(address);

    error NotAuthorized(address);


    // -----------
    // Constructor
    // -----------

    /**
     * @notice Initializes stRWA.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     * @param _asset Will be assigned to `asset`.
     */
    constructor(uint256 mainChainId, address lzEndpoint, address _asset) 
        LayerZeroRebaseTokenUpgradeable(lzEndpoint)
        CrossChainToken(mainChainId)
    {
        _asset.requireNonZeroAddress();
        asset = _asset;
        _disableInitializers();
    }


    /**
     * @notice Initializes stRWA's inherited upgradeables and non-immutable variables.
     * @param owner Initial owner of contract.
     * @param name Name of wrapped token.
     * @param symbol Symbol of wrapped token.
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol
    ) external initializer {
        owner.requireNonZeroAddress();
        __LayerZeroRebaseToken_init(owner, name, symbol);
        _setRebaseIndex(1 ether, 1);
    }


    // --------
    // External
    // --------

    /**
     * @notice This method will update the `rebaseIndex` based on the rewards collected in the TokenSilo.
     * @dev The rebase logic will calculate the % increase in the amount of RWA locked. Based on the % increase,
     * we then increase the rebaseIndex by the same percentage.
     */
    function rebase() external {
        if (msg.sender != rebaseIndexManager && msg.sender != owner()) revert NotAuthorized(msg.sender);
        // get locked balance from token silo
        uint256 locked = tokenSilo.getLockedAmount();
        // call token silo to handle rewards and return newly locked tokens for rebase
        uint256 amountToRebase = tokenSilo.rebaseHelper();
        amountToRebase.requireDifferentUint256(0);
        // calculate percentage increase
        uint256 percentageIncrease = amountToRebase * 1e18 / locked;
        // grab current rebaseIndex and calculate new rebaseIndex delta
        uint256 rebaseIndex = rebaseIndex();
        uint256 delta = rebaseIndex * percentageIncrease / 1e18;
        // increase rebaseIndex with delta
        rebaseIndex += delta;
        _setRebaseIndex(rebaseIndex, 1);
    }

    /**
     * @notice This method allows the owner to set a new address in `tokenSilo`.
     * @param silo New address for `tokenSilo`.
     */
    function setTokenSilo(address payable silo) external onlyOwner {
        silo.requireNonZeroAddress();
        silo.requireDifferentAddress(address(tokenSilo));
        emit TokenSiloUpdated(silo);
        tokenSilo = TokenSilo(silo);
    }

    /**
     * @notice Takes assets and returns a preview of the amount of shares that would be received
     * if the amount assets was deposited via `deposit`.
     */
    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /**
     * @notice Allows a user to deposit amount of `asset` into this contract to receive
     * shares amount of stRWA.
     * @dev I.e. Deposit X RWA to get Y stRWA: X is provided
     * @param assets Amount of asset.
     * @param receiver Address that will be minted tokens.
     */
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        assets.requireDifferentUint256(0);
        receiver.requireNonZeroAddress();

        uint256 amountReceived = _pullAssets(msg.sender, assets);
        _depositIntoTokenSilo(amountReceived);
        shares = assets;

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, amountReceived, shares);
    }

    /**
     * @notice Returns an amount of RWA tokens that would be redeemed if `shares` amount of stRWA tokens
     * were used to redeem.
     */
    function previewRedeem(uint256 shares) external view returns (uint256) {
        uint256 fee = tokenSilo.fee();
        if (fee != 0) {
            return shares - (shares * fee / 100_00);
        } else {
            return shares;
        }
    }

    /**
     * @notice Allows a user to use a specified amount of stRWA to redeem a veRWA lock position of `assets` locked amount.
     * @dev I.e. Redeem X stRWA for Y RWA: X is provided. The Y RWA returned is in the form a single veRWA lock position.
     * @param shares Amount of stRWAs the user wants to use to redeem a governance token.
     * @param receiver Address where the veRWA is transferred to.
     * @param owner Current owner of stRWAs. 'shares` amount will be burned from this address.
     * @return tokenId -> Token identifier of veRWA token transferred to `receiver`.
     * @return assets -> Amount of `asset` in lock redeemed.
     */
    function redeem(uint256 shares, address receiver, address owner) external nonReentrant returns (uint256 tokenId, uint256 assets) {
        shares.requireDifferentUint256(0);
        receiver.requireNonZeroAddress();
        owner.requireNonZeroAddress();

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);
        
        (tokenId, assets) = _redeemFromTokenSilo(shares, receiver);
        emit Redeem(msg.sender, receiver, owner, tokenId, assets, shares);
    }

    /**
     * @notice This setter allows the owner to update the `rebaseIndexManager` state variable.
     * @dev The rebaseIndexManager address has the ability to execute rebase.
     * @param _rebaseIndexManager Address of rebase manager.
     */
    function updateRebaseIndexManager(address _rebaseIndexManager) external {
        if (
            msg.sender != owner() && 
            msg.sender != tokenSilo.rebaseController()
        ) revert NotAuthorized(msg.sender);
        emit RebaseIndexManager(_rebaseIndexManager);
        rebaseIndexManager = _rebaseIndexManager;
    }


    // --------
    // Internal
    // --------

    /**
     * @dev Pulls assets from `from` address of `amount`. Performs a pre and post balance check to 
     * confirm the amount received, and returns that amount.
     */
    function _pullAssets(address from, uint256 amount) private returns (uint256 received) {
        uint256 preBal = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(from, address(this), amount);
        received = IERC20(asset).balanceOf(address(this)) - preBal;
    }

    /**
     * @notice Internal method for depositing $RWA tokens into the tokenSilo.
     * @param amount Amount of $RWA to deposit.
     */
    function _depositIntoTokenSilo(uint256 amount) internal {
        IERC20(asset).forceApprove(address(tokenSilo), amount);
        tokenSilo.depositAndLock(amount);
    }

    /**
     * @notice Internal method for redeeming a veRWA position for a user based on
     * their $stRWA balance.
     */
    function _redeemFromTokenSilo(uint256 assets, address receiver) internal returns (uint256 tokenId, uint256 amountLocked) {
        (tokenId, amountLocked) = tokenSilo.redeemLock(assets, receiver);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     * @dev Allows us to add a permissioned modifier to upgrade this contract.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}