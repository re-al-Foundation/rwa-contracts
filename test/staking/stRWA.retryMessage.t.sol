// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { stRWA as StakedRWA } from "../../src/staking/stRWA.sol";
import { WrappedstRWASatellite } from "../../src/staking/WrappedstRWASatellite.sol";
import { TokenSilo } from "../../src/staking/TokenSilo.sol";
import { RWAToken } from "../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../src/governance/RWAVotingEscrow.sol";
import { RevenueStreamETH } from "../../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../../src/RevenueDistributor.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "../../src/interfaces/IQuoterV2.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";

// local helper imports
import "../utils/Utility.sol";
import "../utils/Constants.sol";

/**
 * @title StakedRWATestUtility
 * @author @chasebrownn
 * @notice This acts as a Utility file for StakedRWA Tests.
 */
contract StakedRWATestUtility is Utility {

    // ~ Contracts ~

    WrappedstRWASatellite public wstRWA = WrappedstRWASatellite(0xE19Bb2e152C770dD15772302f50c3636E24e4c95);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
    }

    function test_retryMessage() public {
        wstRWA.retryMessage(
            10262,
            hex'e19bb2e152c770dd15772302f50c3636e24e4c95e19bb2e152c770dd15772302f50c3636e24e4c95',
            3,
            hex'000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000A00000000000000000000000000000000000000000000000008AC7230489E800000000000000000000000000000000000000000000000000000DE0B6B3A76400000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000001454792B36BF490FC53AC56DB33FD3953B56DF6BAF000000000000000000000000'
        );
    }
}