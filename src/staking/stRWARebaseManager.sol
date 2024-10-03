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
import { ISingleTokenLiquidityProvider } from "../interfaces/ISingleTokenLiquidityProvider.sol";
import { IGauge } from "../interfaces/IGauge.sol";
import { IPair } from "../interfaces/IPair.sol";

/**
 * @title stRWARebaseManager
 * @author chasebrownn
 * @notice This contract manages the rebase and skim logic used to execute rebases on the stRWA contract and post-rebase
 * perform any skims necessary from a pool within the ecosystem.
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
    /// @dev Stores contract reference for SingleTokenLiquidityProvider.
    ISingleTokenLiquidityProvider public singleTokenLiquidityProvider;
    /// @dev Stores contract reference to stRWA-RWA Gauge.
    IGauge public gauge;
    /// @dev stRWA-RWA pool - used for skimming post-rebase.
    IPair public pair;


    // ---------------
    // Events & Errors
    // ---------------

    event pairUpdated(address pair);
    event singleTokenLiquidityProviderUpdated(address provider);
    event gaugeUpdated(address gauge);

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
     * @param _gauge Address of stRWA-RWA gauge.
     * @param _stlp Address of singleTokenLiquidityProvider contract.
     */
    function initialize(address owner, address _pair, address _gauge, address _stlp) external initializer {
        owner.requireNonZeroAddress();

        __Ownable2Step_init();
        _transferOwnership(owner);

        pair = IPair(_pair);
        gauge = IGauge(_gauge);
        singleTokenLiquidityProvider = ISingleTokenLiquidityProvider(_stlp);

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
        emit pairUpdated(_pair);
        pair = IPair(_pair);
    }

    /**
     * @notice Allows the owner to update the `singleTokenLiquidityProvider` address.
     * @dev The singleTokenLiquidityProvider is the address of the SingleTokenLiquidityProvider contract which
     * allows this contact to add one-sided liquidity to the `pair`.
     * @param _stlp New singleTokenLiquidityProvider address.
     */
    function setSingleTokenLiquidityProvider(address _stlp) external onlyOwner {
        _stlp.requireDifferentAddress(address(singleTokenLiquidityProvider));
        _stlp.requireNonZeroAddress();
        emit singleTokenLiquidityProviderUpdated(_stlp);
        singleTokenLiquidityProvider = ISingleTokenLiquidityProvider(_stlp);
    }

    /**
     * @notice Allows the owner to update the `gauge` address.
     * @dev The gauge is the address of the GaugeV2 contract which allows this contact to stake liquidity tokens
     * in exchange for rewards.
     * @param _gauge New gauge address.
     */
    function setGauge(address _gauge) external onlyOwner {
        _gauge.requireDifferentAddress(address(gauge));
        _gauge.requireNonZeroAddress();
        emit gaugeUpdated(_gauge);
        gauge = IGauge(_gauge);
    }


    // --------
    // Internal
    // --------

    /**
     * @notice Internal method for performing a rebase and skim in one execution.
     */
    function _rebaseAndSkim() internal {
        // call rebase on stRWA
        stRWA.rebase();
        // skim
        uint256 skimmed;
        if (address(pair) != address(0)) skimmed = _skim();
        // add to liq and stake
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
     * @notice Performs a one-sided liquidity add and staked liquidity tokens for rewards.
     * @dev The amount referenced when adding to liquidity is the entire contract balance of stRWA tokens.
     * Similarly, all liquidity tokens that are within the contract will also be staked into the gauge.
     */
    function _performBribe() internal {
        // add `amount` to liquidity.
        uint256 amount = stRWA.balanceOf(address(this));
        stRWA.approve(address(singleTokenLiquidityProvider), amount);
        uint256 liquidity = singleTokenLiquidityProvider.addLiquidity(
            pair,
            address(stRWA),
            amount,
            amount/2,
            0
        );
        // stake liquidity tokens.
        //pair.approve(address(gauge), liquidity);
        // TODO: gauge.depositAll();
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}