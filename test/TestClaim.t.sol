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
    RevenueStreamETH public REV_STREAM = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);

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
        vm.createSelectFork(REAL_RPC_URL, 585506);
    }


    // ----------
    // Unit Tests
    // ----------

    function VerifyMessage(bytes32 _hashedMessage, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _hashedMessage));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer;
    }

    function test_revStreamETH_simulation() public {
        // ~ Config ~

        address actor = 0x7a58b76fFD3989dDbCe7BD632fdcF79B50530A69;

            ClaimData memory claimData;
        
            (claimData.amount,
            claimData.cyclesClaimable,
            claimData.amountsClaimable,
            claimData.num,
            claimData.indexes) = REV_STREAM.claimable(actor);
            claimData.currentIndex = REV_STREAM.lastClaimIndex(actor);

        bytes memory signature = hex"5d637afaad02751151e17c207ad6902879bb65e08c2cd5e2ac97d9612208f4cc35d1347e6ec8ebc35ed9515e6b266046a1d3de846c51cb5606de2e9defa517891b";
        uint256 deadline = 1724367568;

        bytes memory header = "\x19Ethereum Signed Message:\n32";

        bytes32 data = keccak256(
            abi.encodePacked(
                actor,
                claimData.amount,
                claimData.currentIndex,
                claimData.indexes,
                claimData.cyclesClaimable,
                claimData.amountsClaimable,
                claimData.num,
                deadline
            )
        );
        //bytes32 prefixedHashMessage = keccak256(abi.encodePacked(header, data));
        //address messageSigner = ECDSA.recover(prefixedHashMessage, signature);

        //emit log_named_address("signer", messageSigner);

        // we need: 0x6Ef3d97A21F4550BF438F6e10C4Dd1b6489de576

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

        (claimData.amount,,,claimData.num,) = REV_STREAM.claimable(actor);
        assertEq(claimData.amount, 0);
        assertEq(claimData.num, 0);
    }
}