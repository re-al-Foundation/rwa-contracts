// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { stRWA as StakedRWA } from "../../src/staking/stRWA.sol";
import { TokenSilo } from "../../src/staking/TokenSilo.sol";
import { stRWARebaseManager } from "../../src/staking/stRWARebaseManager.sol";
import { RWAToken } from "../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../src/governance/RWAVotingEscrow.sol";
import { RevenueStreamETH } from "../../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../../src/RevenueDistributor.sol";
import { ISingleTokenLiquidityProvider } from "../../src/interfaces/ISingleTokenLiquidityProvider.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "../../src/interfaces/IQuoterV2.sol";
import { IRouter } from "../../src/interfaces/IRouter.sol";
import { IPair } from "../../src/interfaces/IPair.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";

// local helper imports
import "../utils/Utility.sol";
import "../utils/Constants.sol";

/**
 * @title StakedRWASkimUtility
 * @author @chasebrownn
 * @notice This test file contains unit tests for verifying proper usage of rebase + skim mechanics.
 */
contract StakedRWASkimUtility is Utility {

    // ~ Contracts ~

    StakedRWA public stRWA = StakedRWA(0xE19Bb2e152C770dD15772302f50c3636E24e4c95);
    TokenSilo public tokenSilo = TokenSilo(payable(0x17Ad18599756A1fCdf8ac61685a17e1BBFce230d));
    stRWARebaseManager public rebaseManager;

    // rwa contracts
    RWAToken public constant rwaToken = RWAToken(0x7F455b0345C161aBc8Ca8FA2bF801Df4914F481C);
    RWAVotingEscrow public constant rwaVotingEscrow = RWAVotingEscrow(0xB79Cf665d0aeDF7A65547421109f4f91F7d1C687);
    RevenueStreamETH public constant revStream = RevenueStreamETH(0x08Cdd24856279641eb7A11D2AaB54e762198FdB7);
    RevenueDistributor public constant revDist = RevenueDistributor(payable(0x48027bfdc9923642F44aa5c199C7eF9f07B3d5D2));

    // pearl contracts
    ISwapRouter public constant SWAP_ROUTER = ISwapRouter(UNREAL_SWAP_ROUTER);
    IQuoterV2 public constant QUOTER = IQuoterV2(UNREAL_QUOTERV2);
    IRouter public constant ROUTER = IRouter(0xaFA5322cc9268E306E3C256B5BB2C2BfFFa4f775);
    ISingleTokenLiquidityProvider public constant SINGLE_TOKEN_PROVIDER = ISingleTokenLiquidityProvider(0xB4F7FE6fd073c6D72dDcBF92A120afdfeF972893);

    // variables
    IWETH public constant WETH = IWETH(UNREAL_WETH);
    address public constant OWNER = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;
    address public constant POOL = 0x82A2d0f3F2FF889F4ecdC096D175136B82B42Cda;
    address public constant GAUGE = 0x4093370686643Fe18c3187075e6385fa27e04a3A;

    function setUp() public virtual {
        vm.createSelectFork(UNREAL_RPC_URL, 878912);

        // ~ Deploy Contracts ~

        // Upgrade stRWA
        vm.startPrank(OWNER);
        stRWA.upgradeToAndCall(address(new StakedRWA(18233, UNREAL_LZ_ENDPOINT_V1, address(rwaToken))), "");

        // Upgrade TokenSilo
        tokenSilo.upgradeToAndCall(address(new TokenSilo(address(stRWA), address(rwaVotingEscrow), address(revStream), address(WETH))), "");

        // Deploy rebaseManager & proxy
        ERC1967Proxy rebaseManagerProxy = new ERC1967Proxy(
            address(new stRWARebaseManager(address(stRWA), address(tokenSilo))),
            abi.encodeWithSelector(stRWARebaseManager.initialize.selector,
                OWNER,
                POOL,
                GAUGE,
                SINGLE_TOKEN_PROVIDER
            )
        );
        rebaseManager = stRWARebaseManager(address(rebaseManagerProxy));

        // ~ Config ~

        // set rebaseManager on token silo -> sets on stRWA as well
        tokenSilo.setRebaseManager(address(rebaseManager));

        _addToLiquidity();
        _createLabels();
        vm.stopPrank();
    }


    // -------
    // Utility
    // -------

    /// @dev Adds liquidity to liquidity pool.
    function _addToLiquidity() internal {
        uint256 liqAmount = 1_000 ether;
        deal(address(rwaToken), address(OWNER), liqAmount);
        _dealstRWA(address(OWNER), liqAmount);

        rwaToken.approve(address(ROUTER), liqAmount);
        stRWA.approve(address(ROUTER), liqAmount);

        ROUTER.addLiquidity(
            address(stRWA),
            address(rwaToken),
            true,
            liqAmount,
            liqAmount,
            0,
            0,
            OWNER,
            block.timestamp
        );
    }

    /// @dev deal doesn't work with stRWA since the storage layout is different.
    function _dealstRWA(address give, uint256 amount) internal {
        bytes32 stRWAStorageLocation = 0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;
        uint256 mapSlot = 2;
        bytes32 slot = keccak256(abi.encode(give, uint256(stRWAStorageLocation) + mapSlot));
        vm.store(address(stRWA), slot, bytes32(amount));
    }

    /// @dev Utility method to store a new variable within stRWA::rebaseIndex via vm.store.
    /// Writes directly to the storage location since `rebaseIndex` is at slot 0.
    function _setRebaseIndex(uint256 index) internal {
        bytes32 RebaseTokenStorageLocation = 0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;
        vm.store(address(stRWA), RebaseTokenStorageLocation, bytes32(index));
        assertEq(stRWA.rebaseIndex(), index);
        emit log_named_uint("New rebaseIndex", index);
    }

    /// @dev Instantiates labels for all global contracts.
    function _createLabels() internal {
        vm.label(address(stRWA), "stRWA");
        vm.label(address(tokenSilo), "TokenSilo");
        vm.label(address(rwaToken), "RWAToken");
        vm.label(address(rwaVotingEscrow), "RWAVotingEscrow");
        vm.label(address(revStream), "RevenueStreamETH");
    }

    /// @dev Utility function for performing rebase on stRWA. Performs state checks post-rebase.
    function _rebase() internal {
        uint256 balance = rwaToken.balanceOf(address(tokenSilo));
        uint256 preLocked = tokenSilo.getLockedAmount();
        uint256 preSupply = rwaToken.totalSupply();
        (uint256 burnAmount,,uint256 rebaseAmount) = tokenSilo.getAmounts(balance);

        vm.prank(OWNER);
        stRWA.rebase();

        // Verify amount burned and amount rebased is correct.
        assertEq(burnAmount, balance * 2 / 10);
        assertEq(rebaseAmount, balance * 8 / 10);
        // Verify tokenSilo has 0 RWA after rebase.
        assertApproxEqAbs(rwaToken.balanceOf(address(tokenSilo)), 0, 1);
        // Verify RWA supply and new locked amount post-rebase.
        assertEq(rwaToken.totalSupply(), preSupply - burnAmount);
        assertEq(tokenSilo.getLockedAmount(), preLocked + rebaseAmount);
    }

    /// @dev Returns the amount of token0 in pair.
    function _reserve0(address pair) internal view returns (uint256 reserve0) {
        (reserve0,,) = IPair(pair).getReserves();
    }

    /// @dev Returns the amount of token1 in pair.
    function _reserve1(address pair) internal view returns (uint256 reserve1) {
        (,reserve1,) = IPair(pair).getReserves();
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies proper state changes when a skim on the pair occurs right after rebase.
    function test_stakedRWA_rebase_then_skim() public {
        // ~ Config ~

        uint256 amountTokens = 10 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        assertEq(stRWA.balanceOf(POOL) - _reserve1(POOL), 0);

        // ~ Execute rebase and skim ~

        _rebase();

        uint256 skimmable = stRWA.balanceOf(POOL) - _reserve1(POOL);
        assertNotEq(skimmable, 0);
        uint256 preBal = stRWA.balanceOf(OWNER);

        IPair(POOL).skim(OWNER);

        // ~ Post-state check ~

        assertApproxEqAbs(stRWA.balanceOf(POOL) - _reserve1(POOL), 0, 2);
        assertApproxEqAbs(stRWA.balanceOf(OWNER), preBal + skimmable, 2);
    }

    /// @dev Verifies proper state changes when RebaseManager::rebase is executed.
    function test_stakedRWA_rebase_from_rebaseManager() public {
        // ~ Config ~

        uint256 amountTokens = 10 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        deal(address(rwaToken), address(tokenSilo), amountTokens);

        assertEq(stRWA.balanceOf(POOL) - _reserve1(POOL), 0);

        // ~ Execute rebase ~

        vm.prank(OWNER);
        rebaseManager.rebase();
        
        // TODO: Complete post-state checks
    }
}