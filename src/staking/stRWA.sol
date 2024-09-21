// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// tangible imports
import { LayerZeroRebaseTokenUpgradeable } from "@tangible-foundation-contracts/tokens/LayerZeroRebaseTokenUpgradeable.sol";
import { CrossChainToken } from "@tangible-foundation-contracts/tokens/CrossChainToken.sol";

// local imports
import { TokenSilo } from "./TokenSilo.sol";
import { CommonValidations } from "../libraries/CommonValidations.sol";

/**
 * @title stRWA
 * @notice This token is a cross-chain token that only rebases on the main chain. This token can only be minted in exchange
 * for $RWA tokens. Once minted, the $RWA tokens will be locked into a veRWA position to begin accruing revenue. The revenue
 * will be claimed and used to rebase; Distributing revenue amongst $stRWA holders.
 */
contract stRWA is UUPSUpgradeable, LayerZeroRebaseTokenUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using CommonValidations for *;

    // ~ State Variables ~

    /// @dev WAD constant uses for conversions.
    uint256 internal constant WAD = 1e18;
    /// @dev Address of token being "wrapped".
    address public immutable asset;
    /// @dev Stores contract reference to the TokenSilo.
    TokenSilo public tokenSilo;


    // ~ Events & Errors ~

    event Deposit(address msgSender, address receiver, uint256 amountReceived, uint256 minted);
    event Redeem(address msgSender, address receiver, address owner, uint256 assets, uint256 burned);
    event TokenSiloUpdated(address);


    // ~ Constructor ~

    /**
     * @notice Initializes stRWA.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     * @param _asset Will be assigned to `asset`.
     */
    constructor(address lzEndpoint, address _asset) 
        LayerZeroRebaseTokenUpgradeable(lzEndpoint)
        CrossChainToken(111188)
    {
        asset = _asset;
        _disableInitializers();
    }


    // ~ Initializer ~

    /**
     * @notice Initializes stRWA's inherited upgradeables.
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


    // ~ Methods ~

    function rebase() external {
        // TODO
        // - calls claim and distribute on tokenSilo
        uint256 amountToRebase = tokenSilo.claim();
    }

    /**
     * TODO
     */
    function setTokenSilo(address silo) external onlyOwner {
        silo.requireNonZeroAddress();
        silo.requireDifferentAddress(address(tokenSilo));

        emit TokenSiloUpdated(silo);
        tokenSilo = TokenSilo(silo);
    }

    /**
     * @notice Takes assets and returns a preview of the amount of shares that would be received
     * if the amount assets was deposited via `deposit`.
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets);
    }

    /**
     * @notice Allows a user to deposit assets amount of `asset` into this contract to receive
     * shares amount of wrapped basket token.
     * @dev I.e. Deposit X RWA to get Y stRWA: X is provided
     * @param assets Amount of asset.
     * @param receiver Address that will be minted wrappd token.
     */
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        assets.requireDifferentUint256(0);
        receiver.requireNonZeroAddress();

        uint256 amountReceived = _pullAssets(msg.sender, assets);
        _depositIntoTokenSilo(amountReceived);
        shares = _convertToShares(amountReceived);

        if (shares != 0) {
            _mint(receiver, shares);
        }

        emit Deposit(msg.sender, receiver, amountReceived, shares);
    }

    /**
     * @notice Returns an amount of basket tokens that would be redeemed if `shares` amount of wrapped tokens
     * were used to redeem.
     */
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares);
    }

    /**
     * @notice Allows a user to use a specified amount of wrapped basket tokens to redeem basket tokens.
     * @dev I.e. Redeem X stRWA for Y RWA: X is provided
     * @param shares Amount of wrapped basket tokens the user wants to use in order to redeem basket tokens.
     * @param receiver Address where the basket tokens are transferred to.
     * @param owner Current owner of wrapped basket tokens. 'shares` amount will be burned from this address.
     */
    function redeem(uint256 shares, address receiver, address owner) external nonReentrant returns (uint256 assets) {
        shares.requireDifferentUint256(0);
        receiver.requireNonZeroAddress();
        owner.requireNonZeroAddress();

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        assets = _convertToAssets(shares);

        if (assets != 0) {
            _redeemFromTokenSilo(assets, receiver);
        }

        emit Redeem(msg.sender, receiver, owner, assets, shares);
    }


    // ~ Internal Methods ~

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        return Math.mulDiv(assets, rebaseIndex(), WAD);
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return Math.mulDiv(shares, WAD, rebaseIndex());
    }

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
     * @dev Transfers an `amount` of `asset` to the `to` address.
     */
    // function _pushAssets(address to, uint256 amount) private {
    //     IERC20(asset).safeTransfer(to, amount);
    // }

    function _depositIntoTokenSilo(uint256 amount) internal {
        IERC20(asset).forceApprove(address(tokenSilo), amount);
        tokenSilo.depositAndLock(amount);
    }

    function _redeemFromTokenSilo(uint256 assets, address receiver) internal {
        tokenSilo.redeemLock(assets, receiver);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // ~ LayerZero overrides ~

    // function sendFrom(
    //     address _from,
    //     uint16 _dstChainId,
    //     bytes calldata _toAddress,
    //     uint256 _amount,
    //     address payable _refundAddress,
    //     address _zroPaymentAddress,
    //     bytes calldata _adapterParams
    // ) public payable override(IOFTCore, OFTCoreUpgradeable) {
    //     _send(
    //         _from,
    //         _dstChainId,
    //         _toAddress,
    //         _amount,
    //         _refundAddress,
    //         _zroPaymentAddress,
    //         _adapterParams
    //     );
    // }

    // function _debitFrom(
    //     address _from,
    //     uint16,
    //     bytes memory,
    //     uint256 _amount
    // ) internal override returns (uint256) {
    //     address spender = _msgSender();
    //     if (_from != spender) _spendAllowance(_from, spender, _amount);
    //     _transfer(_from, address(this), _amount);
    //     return _amount;
    // }

    // function _creditTo(
    //     uint16,
    //     address _toAddress,
    //     uint256 _amount
    // ) internal override returns (uint256) {
    //     _transfer(address(this), _toAddress, _amount);
    //     return _amount;
    // }
}