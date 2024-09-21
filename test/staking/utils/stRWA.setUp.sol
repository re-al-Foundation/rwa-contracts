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

// local helper imports
import "../../utils/Utility.sol";
import "../../utils/Constants.sol";

/**
 * @title StakedRWATestUtility
 * @author @chasebrownn
 * @notice This acts as a Utility 
 */
contract StakedRWATestUtility is Utility {

    // ~ Contracts ~

    StakedRWA public stRWA;
    TokenSilo public tokenSilo;

    RWAToken public rwaToken = RWAToken(0x4644066f535Ead0cde82D209dF78d94572fCbf14);
    RWAVotingEscrow public rwaVotingEscrow = RWAVotingEscrow(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);
    RevenueStreamETH public revStream = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);

    function setUp() public virtual {
        vm.createSelectFork(REAL_RPC_URL, 716890);

        // ~ Deploy Contracts ~

        // Deploy stRWA & proxy
        ERC1967Proxy stRWAProxy = new ERC1967Proxy(
            address(new StakedRWA(REAL_LZ_ENDPOINT_V1, address(rwaToken))),
            abi.encodeWithSelector(StakedRWA.initialize.selector,
                MULTISIG,
                "Liquid Staked RWA",
                "stRWA"
            )
        );
        stRWA = StakedRWA(address(stRWAProxy));

        // Deploy tokenSilo & proxy
        ERC1967Proxy siloProxy = new ERC1967Proxy(
            address(new TokenSilo(address(stRWA), address(rwaVotingEscrow), address(revStream))),
            abi.encodeWithSelector(TokenSilo.initialize.selector,
                MULTISIG
            )
        );
        tokenSilo = TokenSilo(address(siloProxy));

        // ~ Config ~

        // set tokenSilo on stRWA
        vm.prank(MULTISIG);
        stRWA.setTokenSilo(address(tokenSilo));

        // exclude tokenSilo from fees
        vm.prank(MULTISIG);
        rwaToken.excludeFromFees(address(tokenSilo), true);

        _createLabels();
    }

    // -------
    // Utility
    // -------

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