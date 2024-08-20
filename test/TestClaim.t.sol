// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// local imports
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../src/RevenueDistributor.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { DelegateFactory } from "../src/governance/DelegateFactory.sol";
import { Delegator } from "../src/governance/Delegator.sol";

// local helper imports
import { Utility } from "./utils/Utility.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import "./utils/Constants.sol";

/**
 * @title RevenueStreamETHSignatureTest
 * @author @chasebrownn
 * @notice This test file contains integration tests to verify the implementation of signature claims
 * in the RevenueStreamETH contract.
 */
contract RevenueStreamETHSignatureTest is Utility {

    // contracts
    RevenueStreamETH public REV_STREAM = RevenueStreamETH(0x08Cdd24856279641eb7A11D2AaB54e762198FdB7);

    // Actors
    uint256 public privateKey = 1234;
    address public constant signer = 0x6Ef3d97A21F4550BF438F6e10C4Dd1b6489de576;

    struct ClaimData {
        uint256 amount;
        uint256 currentIndex;
        uint256[] cyclesClaimable;
        uint256[] amountsClaimable;
        uint256 num;
        uint256 indexes;
    }

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL, 368272);
    }


    // ----------
    // Unit Tests
    // ----------

    function test_revStreamETH_simulation() public {
        // ~ Config ~

        address actor = 0x54792B36bf490FC53aC56dB33fD3953B56DF6baF;

        ClaimData memory claimData;
        
        (claimData.amount,
        claimData.cyclesClaimable,
        claimData.amountsClaimable,
        claimData.num,
        claimData.indexes) = REV_STREAM.claimable(actor);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(actor);

        bytes memory signature = hex"42a35e8fe639255c0a399a785ddb34d5fc552dfa35b0a9e06adc32b1f24b16da3fdec01596c7ac913b0225e86e71a7dee841136ab0d2dbbe698c8a2adbf8ec4c1b";
        uint256 deadline = 1724180898;

        vm.prank(actor);
        REV_STREAM.claimWithSignature(
            claimData.amount,
            claimData.currentIndex,
            claimData.indexes,
            claimData.cyclesClaimable,
            claimData.amountsClaimable,
            claimData.num,
            deadline,
            signature
        );
    }
}