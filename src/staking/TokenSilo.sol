// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

// local imports
import { RWAVotingEscrow } from "../governance/RWAVotingEscrow.sol";
import { VotingMath } from "../governance/VotingMath.sol";
import { RevenueStreamETH } from "../RevenueStreamETH.sol";
import { RWAToken } from "../RWAToken.sol";
import { CommonValidations } from "../libraries/CommonValidations.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import { IWETH } from "../interfaces/IWETH.sol";

/**
 * @title TokenSilo
 * @notice TODO
 */
contract TokenSilo is UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for RWAToken;
    using SafeERC20 for IERC20;
    using CommonValidations for *;

    // ---------------
    // State Variables
    // ---------------

    struct DistributionRatios {
        /// @dev Ratio of rewards that will be burned.
        uint256 burn;
        /// @dev Ratio of rewards that will be locked, but not used for rebase.
        uint256 retain;
        /// @dev Ratio of rewards that will be locked and used for rebase.
        uint256 rebase;
        /// @dev burn + retain + rebase.
        uint256 total;
    }

    /// @dev Stores the maximum vesting duration for a lock period.
    uint256 public constant MAX_VESTING_DURATION = VotingMath.MAX_VESTING_DURATION;
    /// @dev Stores contract reference to WETH.
    IWETH public immutable WETH;
    /// @dev Stores contract reference to SwapRouter.
    ISwapRouter public immutable router;
    /// @dev Stores contact address for stRWA.
    address public immutable stRWA;
    /// @dev Stores contact reference for $RWA token.
    RWAToken public immutable rwaToken;
    /// @dev Stores contract reference for veRWA.
    RWAVotingEscrow public immutable votingEscrowRWA;
    /// @dev Contract reference for RevenueStreamETH.
    RevenueStreamETH public immutable revStream;
    /// @dev Stores a supported selector, given the `target` address. Prevents misuse.
    mapping(address target => mapping(bytes4 selector => bool approved)) public fetchSelector;
    /// @dev If true, address can call claim and convertRewardToken.
    mapping(address => bool) public isFundsManager;
    /// @dev TokenId of veRWA token stored in this contract.
    uint256 public masterTokenId;
    /// @dev Distribution ratios of ETH rewards.
    DistributionRatios public distribution;
    /// @dev Stores contract address of rebase controller.
    address public rebaseController;


    // ---------------
    // Events & Errors
    // ---------------

    event ETHRewardsClaimed(uint256 amount);
    event TokenMinted(uint256 tokenId);
    event RWADeposited(uint256 amount);
    event TokenRedeemed(uint256 tokenId, address indexed recipient);
    event ETHReceived(address sender, uint256 amount);
    event DistributionUpdated(uint256 burn, uint256 retain, uint256 rebase);
    event ETHConverted(uint256 amountETH, uint256 amountOut);
    event FundsManagerSet(address indexed account, bool);
    event RebaseControllerUpdated(address indexed newController);

    error NotAuthorized(address);


    // ---------
    // Modifiers
    // ---------

    modifier onlyStakedRWA() {
        if (msg.sender != stRWA) revert NotAuthorized(msg.sender);
        _;
    }

    modifier onlyFundsManager() {
        if (msg.sender != owner() && !isFundsManager[msg.sender]) revert NotAuthorized(msg.sender);
        _;
    }


    // -----------
    // Constructor
    // -----------

    /**
     * @notice Initializes TokenSilo.
     */
    constructor(address _stRWA, address _veRWA, address _revStream, address _router) {
        _stRWA.requireNonZeroAddress();
        _veRWA.requireNonZeroAddress();
        _revStream.requireNonZeroAddress();
        _router.requireNonZeroAddress();

        stRWA = _stRWA;
        votingEscrowRWA = RWAVotingEscrow(_veRWA);
        rwaToken = RWAToken(address(votingEscrowRWA.getLockedToken()));
        revStream = RevenueStreamETH(_revStream);
        router = ISwapRouter(_router);
        WETH = IWETH(router.WETH9());

        _disableInitializers();
    }

    /**
     * @notice TODO
     */
    function initialize(address owner) external initializer {
        owner.requireNonZeroAddress();
        __Ownable2Step_init();
        _transferOwnership(owner);
    }


    // --------
    // External
    // --------

    /**
     * @notice This method allows address(this) to receive ETH.
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function depositAndLock(uint256 amount) external onlyStakedRWA {
        _pullAssets(msg.sender, amount);
        if (masterTokenId != 0) {
            // mint and merge
            _merge(_mint(amount));
        } else {
            // mint and assign to masterTokenId
            masterTokenId = _mint(amount);
        }
    }

    function redeemLock(uint256 amount, address recipient) external onlyStakedRWA returns (uint256 tokenId) {
        if (amount < getLockedAmount()) {
            tokenId = _split(amount);
        } else {
            tokenId = masterTokenId;
            masterTokenId = 0;
        }
        _transferToken(tokenId, recipient);
    }

    function claim() external onlyFundsManager returns (uint256 claimed) {
        claimed = revStream.claimETH();
        claimed.requireDifferentUint256(0);
        WETH.deposit{value:claimed}();
    }

    /**
     * @notice Converts a specific amount of ETH to RWA.
     * @dev Contains a check to verify that the target address and selector are correct
     * to avoid exploits. Follows the same interface as RevenueDistributor::convertRewardToken
     * to allow for the w3f to be used without revision.
     * @param amount Amount ETH to convert.
     * @param target Target address for conversion.
     * @param data Call data for conversion.
     * @return amountOut Amount RWA received.
     */
    function convertRewardToken(
        address /**token */,
        uint256 amount,
        address target,
        bytes calldata data
    ) external onlyFundsManager returns (uint256 amountOut) {
        amount.requireSufficientFunds(WETH.balanceOf(address(this)));
        require(fetchSelector[target][bytes4(data[0:4])], "invalid selector");

        uint256 preBal = rwaToken.balanceOf(address(this));

        IERC20(address(WETH)).forceApprove(target, amount);
        (bool success, ) = target.call(data);
        require(success, "low swap level call failed");

        uint256 postBal = rwaToken.balanceOf(address(this));
        amountOut = postBal - preBal;

        require(amountOut != 0, "no tokens received");

        emit ETHConverted(amount, amountOut);
    }

    function rebaseHelper() external onlyStakedRWA returns (uint256) {
        uint256 bal = rwaToken.balanceOf(address(this));
        bal.requireDifferentUint256(0);

        (uint256 amountToBurn, uint256 amountToRetain, uint256 amountForRebase) = getAmounts(bal);

        if (amountToBurn != 0) _burn(amountToBurn);

        uint256 toLock = amountToRetain + amountForRebase;
        if (toLock != 0) {
            _merge(_mint(toLock));
        }

        return amountForRebase;
    }

    function updateRatios(uint256 _burn, uint256 _retain, uint256 _rebase) external onlyOwner {
        emit DistributionUpdated(_burn, _retain, _rebase);

        distribution.burn = _burn;
        distribution.retain = _retain;
        distribution.rebase = _rebase;
        distribution.total = _burn + _retain + _rebase;
    }

    /**
     * @notice This method sets the verified function call for a `target`.
     * @dev If a selector is not assigned, we will not be able to call `target` to convert revenue tokens.
     * @param target Target contract address where `selector` resides.
     * @param selector Function selector for desired callable method for conversion.
     *
     * @dev Usage:
     *    If we wanted to call `swapExactTokensForETH` on the local UniswapV2Router to swap revenue tokens for ETH.
     *    We would call this method with the following arguments:
     *        target == address(uniswapV2Router)
     *        selector == bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"))
     */
    function setSelectorForTarget(address target, bytes4 selector, bool isApproved) external onlyOwner {
        fetchSelector[target][selector] = isApproved;
    }

    /**
     * @notice Permissiond method to assign whether a `account` address can claim & swap ETH rewards.
     * @param account Address being granted (or revoked) permission to manage rewards.
     * @param isManager If true, `account` can distribute revenue.
     */
    function setFundsManager(address account, bool isManager) external onlyOwner {
        account.requireNonZeroAddress();
        emit FundsManagerSet(account, isManager);
        isFundsManager[account] = isManager;
    }

    /**
     * @notice This method allows the factory owner to update the `rebaseController` state variable.
     * @param controller New address for `rebaseController`.
     */
    function setRebaseController(address controller) external onlyOwner {
        controller.requireNonZeroAddress();
        emit RebaseControllerUpdated(controller);
        rebaseController = controller;
    }


    // ------
    // Public
    // ------

    function claimable() public view returns (uint256 claimable) {
        (claimable,) = revStream.claimable(address(this));
    }

    function getLockedAmount() public view  returns (uint256) {
        return votingEscrowRWA.getLockedAmount(masterTokenId);
    }

    function getAmounts(uint256 claimAmount) public view returns (
        uint256 amountToBurn,
        uint256 amountToRetain,
        uint256 amountForRebase
    ) {
        uint256 total = distribution.total;
        amountToBurn = claimAmount * distribution.burn / total;
        amountToRetain = claimAmount * distribution.retain / total;
        amountForRebase = claimAmount * distribution.rebase / total;
    }


    // --------
    // Internal
    // --------

    /**
     * @dev Pulls assets from `from` address of `amount`. Performs a pre and post balance check to 
     * confirm the amount received, and returns that amount.
     */
    function _pullAssets(address from, uint256 amount) private returns (uint256 received) {
        uint256 preBal = rwaToken.balanceOf(address(this));
        rwaToken.safeTransferFrom(from, address(this), amount);
        received = rwaToken.balanceOf(address(this)) - preBal;
    }

    /**
     * @dev Transfers an `amount` of `rwaToken` to the `to` address.
     */
    function _pushAssets(address to, uint256 amount) private {
        rwaToken.safeTransfer(to, amount);
    }

    function _mint(uint256 amount) internal returns (uint256) {
        rwaToken.forceApprove(address(votingEscrowRWA), amount);
        return votingEscrowRWA.mint({
            _receiver: address(this),
            _lockedBalance: uint208(amount),
            _duration: MAX_VESTING_DURATION
        });
    }

    function _merge(uint256 tokenToMerge) internal {
        votingEscrowRWA.merge({
            tokenId: tokenToMerge,
            intoTokenId: masterTokenId
        });
    } 

    function _split(uint256 amountToSplit) internal returns (uint256) {
        uint256[] memory split = new uint256[](2);
        split[0] = getLockedAmount() - amountToSplit;
        split[1] = amountToSplit;

        uint256[] memory tokenIds = votingEscrowRWA.split({
            tokenId: masterTokenId,
            shares: split
        });
        return tokenIds[1];
    }

    function _burn(uint256 amount) internal {
        rwaToken.burn(amount);
    }

    function _transferToken(uint256 tokenId, address recipient) internal {
        votingEscrowRWA.transferFrom(address(this), recipient, tokenId);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}