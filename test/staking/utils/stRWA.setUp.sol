// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { stRWA as StakedRWA } from "../../../src/staking/stRWA.sol";
import { TokenSilo } from "../../../src/staking/TokenSilo.sol";
import { RWAToken } from "../../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";
import { ISwapRouter } from "../../../src/interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "../../../src/interfaces/IQuoterV2.sol";
import { IWETH } from "../../../src/interfaces/IWETH.sol";

// local helper imports
import "../../utils/Utility.sol";
import "../../utils/Constants.sol";

/**
 * @title StakedRWATestUtility
 * @author @chasebrownn
 * @notice This acts as a Utility file for StakedRWA Tests.
 */
contract StakedRWATestUtility is Utility {

    // ~ Contracts ~

    StakedRWA public stRWA;
    TokenSilo public tokenSilo;

    // rwa contracts
    RWAToken public constant rwaToken = RWAToken(0x4644066f535Ead0cde82D209dF78d94572fCbf14);
    RWAVotingEscrow public constant rwaVotingEscrow = RWAVotingEscrow(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);
    RevenueStreamETH public constant revStream = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);
    RevenueDistributor public constant revDist = RevenueDistributor(payable(0x7a2E4F574C0c28D6641fE78197f1b460ce5E4f6C));

    // pearl contracts
    ISwapRouter public constant router = ISwapRouter(0xa1F56f72b0320179b01A947A5F78678E8F96F8EC);
    IQuoterV2 public constant quoter = IQuoterV2(0xDe43aBe37aB3b5202c22422795A527151d65Eb18);

    // variables
    IWETH public constant WETH = IWETH(0x90c6E93849E06EC7478ba24522329d14A5954Df4);

    function setUp() public virtual {
        vm.createSelectFork(REAL_RPC_URL, 716890);

        // ~ Deploy Contracts ~

        // Deploy stRWA & proxy
        ERC1967Proxy stRWAProxy = new ERC1967Proxy(
            address(new StakedRWA(111188, REAL_LZ_ENDPOINT_V1, address(rwaToken))),
            abi.encodeWithSelector(StakedRWA.initialize.selector,
                MULTISIG,
                "Liquid Staked RWA",
                "stRWA"
            )
        );
        stRWA = StakedRWA(address(stRWAProxy));

        // Deploy tokenSilo & proxy
        ERC1967Proxy siloProxy = new ERC1967Proxy(
            address(new TokenSilo(address(stRWA), address(rwaVotingEscrow), address(revStream), address(router))),
            abi.encodeWithSelector(TokenSilo.initialize.selector,
                MULTISIG
            )
        );
        tokenSilo = TokenSilo(payable(address(siloProxy)));

        // ~ Config ~

        // set tokenSilo on stRWA
        vm.prank(MULTISIG);
        stRWA.setTokenSilo(payable(address(tokenSilo)));

        // upgrade RWAToken
        _upgradeRWAToken();

        // exclude tokenSilo from fees & set to burn
        vm.prank(MULTISIG);
        rwaToken.setTokenSilo(address(tokenSilo));

        // owner sets ratios on tokenSilo
        vm.prank(MULTISIG);
        tokenSilo.updateRatios(2, 0, 8);

        // owner sets selector on tokenSilo for approved swaps
        vm.prank(MULTISIG);
        tokenSilo.setSelectorForTarget(
            address(router),
            bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))")),
            true
        );

        _createLabels();
        _initStateCheck();
    }

    // -------
    // Utility
    // -------

    /// @dev Verifies initial state.
    function _initStateCheck() internal {
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);
        assertEq(tokenSilo.masterTokenId(), 0);
    }

    /// @dev Upgrades the current RWAToken contract on re.al.
    function _upgradeRWAToken() internal {
        vm.startPrank(MULTISIG);
        rwaToken.upgradeToAndCall(address(new RWAToken()), "");
        vm.stopPrank();
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
}