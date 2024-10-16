// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

// local imports
import { stRWA as StakedRWA } from "./stRWA.sol";
import { CommonValidations } from "../libraries/CommonValidations.sol";
import { IBribe } from "../interfaces/IBribe.sol";
import { IGauge } from "../interfaces/IGauge.sol";
import { IPair } from "../interfaces/IPair.sol";

/**
 * @title stRWARebaseManager
 * @author chasebrownn
 * @notice This contract manages the rebase and skim logic used to execute rebases on the stRWA contract and post-rebase
 * performs a skim of excess stRWA in the pool. The skimmed stRWA will be used for bribes via the PearlV2 Bribe contract.
 */
contract stRWARebaseManager is UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;
    using CommonValidations for *;

    // ---------------
    // State Variables
    // --------------- 

    /// @dev Stores contact address for stRWA.
    StakedRWA public immutable stRWA;
    /// @dev Stores contact address for TokenSilo.
    address public immutable tokenSilo;
    /// @dev Stores contract reference for Bribe.
    IBribe public bribe;
    /// @dev stRWA-RWA pool - used for skimming post-rebase.
    IPair public pair;


    // ---------------
    // Events & Errors
    // ---------------

    event PairUpdated(address pair);
    event BribeUpdated(address provider);

    error NotAuthorized(address);


    // ---------
    // Modifiers
    // ---------

    /// @dev Modifier for verifying msg.sender is either owner or tokenSilo.
    modifier onlyTokenSilo {
        if (msg.sender != tokenSilo && msg.sender != owner()) revert NotAuthorized(msg.sender);
        _;
    }


    // -----------
    // Constructor
    // -----------

    /**
     * @notice Initializes TokenSilo immutables.
     * @param _stRWA Contract address for stRWA.
     * @param _silo Contract address for tokenSilo.
     */
    constructor(address _stRWA, address _silo) {
        _stRWA.requireNonZeroAddress();
        _silo.requireNonZeroAddress();

        stRWA = StakedRWA(_stRWA);
        tokenSilo = _silo;

        _disableInitializers();
    }

    /**
     * @notice Initializes TokenSilo non-immutables.
     * @param owner Initial owner of contract.
     * @param _pair Address of stRWA-RWA pool.
     * @param _bribe Address of bribe contract.
     */
    function initialize(address owner, address _pair, address _bribe) external initializer {
        owner.requireNonZeroAddress();

        __Ownable2Step_init();
        _transferOwnership(owner);

        pair = IPair(_pair);
        bribe = IBribe(_bribe);

        stRWA.disableRebase(address(this), true);
    }


    // --------
    // External
    // --------

    /**
     * @notice This method executes a rebase and skim.
     * @dev Only callable by either the owner or the token silo contract.
     */
    function rebase() external onlyTokenSilo {
        _rebaseAndSkim();
    }

    /**
     * @notice Allows the owner to update the `pair` address.
     * @dev The pair is the address of an stRWA pool within the pearl v1 ecosystem. We store the address
     * so this cotnract can perform any skims post-rebase of any excess stRWA within the pool.
     * @param _pair Pair address.
     */
    function setPair(address _pair) external onlyOwner {
        _pair.requireDifferentAddress(address(pair));
        _pair.requireNonZeroAddress();
        emit PairUpdated(_pair);
        pair = IPair(_pair);
    }

    /**
     * @notice Allows the owner to update the `bribe` address.
     * @dev The bribe is the address of the Bribe contract which
     * allows this contract to bribe it's skimmed stRWA.
     * @param _bribe New bribe address.
     */
    function setBribe(address _bribe) external onlyOwner {
        _bribe.requireDifferentAddress(address(bribe));
        _bribe.requireNonZeroAddress();
        emit BribeUpdated(_bribe);
        bribe = IBribe(_bribe);
    }


    // --------
    // Internal
    // --------

    /**
     * @notice Internal method for performing a rebase, skim, and bribe.
     */
    function _rebaseAndSkim() internal {
        // call rebase on stRWA
        stRWA.rebase();
        // skim
        uint256 skimmed;
        if (address(pair) != address(0)) skimmed = _skim();
        // bribe skimmed stRWA
        if (skimmed != 0) _performBribe();
    }

    /**
     * @notice Performs a skim on the `pair` address stored.
     * @dev This method also does a pre and post balance check to verify the amount of stRWA this
     * contract received post-skim.
     * @param received Amount of stRWA received from skim.
     */
    function _skim() internal returns (uint256 received) {
        uint256 preBal = stRWA.balanceOf(address(this));
        pair.skim(address(this));
        received = stRWA.balanceOf(address(this)) - preBal;
    }

    /**
     * @notice Performs a bribe by depositing into bribe contract.
     * @dev The amount added to bribes is the amount of stRWA in the contract balance.
     */
    function _performBribe() internal {
        // add `amount` to liquidity.
        uint256 amount = stRWA.balanceOf(address(this));
        stRWA.approve(address(bribe), amount);
        bribe.notifyRewardAmount(address(stRWA), amount);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}