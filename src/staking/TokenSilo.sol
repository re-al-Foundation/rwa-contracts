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
import { CommonValidations } from "../libraries/CommonValidations.sol";

/**
 * @title TokenSilo
 * @notice TODO
 */
contract TokenSilo is UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------

    struct DistributionRatios {
        uint256 burn;
        uint256 retain;
        uint256 rebase;
        uint256 total;
    }

    /// @dev Stores the maximum vesting duration for a lock period.
    uint256 public constant MAX_VESTING_DURATION = VotingMath.MAX_VESTING_DURATION;

    address public immutable stRWA;

    IERC20 public immutable rwaToken;

    RWAVotingEscrow public immutable votingEscrowRWA;
    /// @dev Contract reference for RevenueStreamETH.
    RevenueStreamETH public immutable revStream;

    uint256 public masterTokenId;

    DistributionRatios public distribution;


    // ---------------
    // Events & Errors
    // ---------------

    event ETHRewardsClaimed(uint256 amount);
    event TokenMinted(uint256 tokenId);
    event RWADeposited(uint256 amount);
    event TokenRedeemed(uint256 tokenId, address recipient);

    error NotAuthorized(address);


    // ---------
    // Modifiers
    // ---------

    modifier onlyStakedRWA() {
        if (msg.sender != stRWA) revert NotAuthorized(msg.sender);
        _;
    }


    // -----------
    // Constructor
    // -----------

    /**
     * @notice Initializes TokenSilo.
     */
    constructor(address _stRWA, address _veRWA, address _revStream) {
        stRWA = _stRWA;
        votingEscrowRWA = RWAVotingEscrow(_veRWA);
        rwaToken = votingEscrowRWA.getLockedToken();
        revStream = RevenueStreamETH(_revStream);

        _disableInitializers();
    }

    /**
     * @notice TODO
     */
    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
    }


    // --------
    // External
    // --------

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

    function claim() external onlyStakedRWA returns (uint256) {
        uint256 claimed = revStream.claimETH();
        uint256 amountTokens = _swap(claimed);

        uint256 total = distribution.total;
        uint256 amountToBurn = amountTokens * distribution.burn / total;
        uint256 amountToRetain = amountTokens * distribution.retain / total;
        uint256 amountForRebase = amountTokens * distribution.rebase / total;

        _burn(amountToBurn);
        _merge(_mint(amountToRetain + amountForRebase));

        return amountForRebase;
    }

    function updateRatios() external onlyOwner {} // TODO


    // ------
    // Public
    // ------

    function claimable() public view returns (uint256 claimable) {
        (claimable,) = revStream.claimable(address(this));
    }

    function getLockedAmount() public view  returns (uint256) {
        return votingEscrowRWA.getLockedAmount(masterTokenId);
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

    function _swap(uint256 amountETH) internal returns (uint256) {
        // TODO
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
        // TODO: Might need to add new method on RWAToken to allow this contract to burn
    }

    function _transferToken(uint256 tokenId, address recipient) internal {
        votingEscrowRWA.transferFrom(address(this), recipient, tokenId);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}