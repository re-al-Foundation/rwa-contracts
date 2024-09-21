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
    RevenueDistributor public REV_DISTRIBUTOR = RevenueDistributor(payable(0x7a2E4F574C0c28D6641fE78197f1b460ce5E4f6C));
    RWAVotingEscrow public VE_RWA = RWAVotingEscrow(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);

    // Actors
    uint256 public constant delegatedTokenId = 1555;
    
    uint256 public privateKey = 12345;
    address public signer;

    struct ClaimData {
        uint256 amount;
        uint256 currentIndex;
        uint256 indexes;
    }

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 184960);

        // upgrade RevenueStreamETH -> gives us claimWithSignature
        vm.startPrank(MULTISIG);
        RevenueStreamETH newRevStream = new RevenueStreamETH();
        REV_STREAM.upgradeToAndCall(address(newRevStream), "");
        vm.stopPrank();

        // create address for signer from pk
        signer = vm.addr(privateKey);

        // set signer on RevStream
        vm.prank(MULTISIG);
        REV_STREAM.setSigner(signer);

        // multisig transfers token to new JOE address
        vm.prank(MULTISIG);
        VE_RWA.transferFrom(MULTISIG, JOE, delegatedTokenId);

        // distribute some ETH so JOE has some to claim
        uint256 amount = 1 ether;
        vm.deal(address(REV_DISTRIBUTOR), amount);
        vm.prank(address(REV_DISTRIBUTOR));
        REV_STREAM.depositETH{value: amount}();
        skip(1);
    }


    // -------
    // Utility
    // -------

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }
    
    /// @notice packs v, r, s into signature bytes
    function _packRsv(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        bytes memory sig = new bytes(65);
        assembly {
            mstore(add(sig, 32), r)
            mstore(add(sig, 64), s)
            mstore8(add(sig, 96), v)
        }
        return sig;
    }

    /// @dev Takes a data packet via claimData and uses the global private key to sign the data packet and returns
    /// the packed signature.
    function _sign(address account, ClaimData memory claimData) internal view returns (bytes memory) {
        // signer signs data hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            getEthSignedMessageHash(
                keccak256(
                    // create data hash
                    abi.encodePacked(
                        account,
                        claimData.amount,
                        claimData.currentIndex,
                        claimData.indexes,
                        block.timestamp
                    )
                )
            )
        );

        return _packRsv(v, r, s);
    }

    /// @dev This internal method will use the `signer` PK to sign a data packet for the account to then execute
    /// a call to claimWithSignature.
    function _signAndClaim(address account, ClaimData memory claimData) internal {
        // claimWithSignature
        vm.prank(account);
        REV_STREAM.claimWithSignature(
            claimData.amount,
            claimData.currentIndex,
            claimData.indexes,
            block.timestamp,
            _sign(account, claimData)
        );
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies proper usage of RevenueStreamETH::claimWithSignature.
    /// @dev Gas comparison:
    ///      - Using claimWithSignature -> 144476 gas -> $0.09
    ///      - Using claimETH -> 10815582 gas -> $7.18
    function test_revStreamETH_claimWithSignature_claimAll() public {
        // ~ Config ~

        ClaimData memory claimData;

        (claimData.amount,
        claimData.indexes) = REV_STREAM.claimable(JOE);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        // ~ Pre-state check ~

        uint256 preBal = JOE.balance;

        // ~ Execute claimWithSignature ~

        _signAndClaim(JOE, claimData);

        // ~ Post-state check ~

        assertEq(JOE.balance, preBal + claimData.amount);
        assertEq(REV_STREAM.lastClaimIndex(JOE), claimData.currentIndex + claimData.indexes);
    }

    /// @dev Verifies proper usage of RevenueStreamETH::claimWithSignature when not all indexes were claimed at once.
    function test_revStreamETH_claimWithSignature_claimMinusOne() public {
        // ~ Config ~

        ClaimData memory claimData;

        (uint256 fullAmount, uint256 totalIndexes) = REV_STREAM.claimable(JOE);
        (claimData.amount,
        claimData.indexes) = REV_STREAM.claimableIncrement(JOE, totalIndexes-1);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        // ~ Pre-state check ~

        uint256 preBal = JOE.balance;

        // ~ Execute claimWithSignature ~

        _signAndClaim(JOE, claimData);

        // ~ Post-state check 1 ~

        assertEq(claimData.amount, 0);
        assertEq(REV_STREAM.lastClaimIndex(JOE), claimData.currentIndex + claimData.indexes);

        (claimData.amount, claimData.indexes) = REV_STREAM.claimable(JOE);
        assertEq(claimData.indexes, 1);
        
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        // ~ Execute claimWithSignature ~

        _signAndClaim(JOE, claimData);

        // ~ Post-state check 2 ~

        assertEq(claimData.amount, fullAmount);
        assertEq(JOE.balance, preBal + claimData.amount);
        assertEq(REV_STREAM.lastClaimIndex(JOE), claimData.currentIndex + claimData.indexes);
    }

    /// @dev Verifies only the designated signer can sign data hashes for claimWithSignature.
    function test_revStreamETH_claimWithSignature_invalidSigner_fuzzing(uint256 attackerPK) public {
        attackerPK = bound(attackerPK, 1, 1_000 * 1e18);

        address attacker = vm.addr(attackerPK);
        ClaimData memory claimData;

        (claimData.amount, claimData.indexes) = REV_STREAM.claimable(JOE);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        // attacker signs data hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            attackerPK,
            getEthSignedMessageHash(
                keccak256(
                    // create data hash
                    abi.encodePacked(
                        JOE,
                        claimData.amount,
                        claimData.currentIndex,
                        claimData.indexes,
                        block.timestamp
                    )
                )
            )
        );

        // claimWithSignature -> revert
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RevenueStreamETH.InvalidSigner.selector, attacker));
        REV_STREAM.claimWithSignature(
            claimData.amount,
            claimData.currentIndex,
            claimData.indexes,
            block.timestamp,
            _packRsv(v, r, s)
        );
    }

    /// @dev Verifies the currentIndex input has to be equal to the lastClaimIndex.
    function test_revStreamETH_claimWithSignature_invalidIndex_fuzzing(uint256 currentIndex) public {
        currentIndex = bound(currentIndex, 1, 1_000 * 1e18);
        ClaimData memory claimData;

        (claimData.amount, claimData.indexes) = REV_STREAM.claimable(JOE);

        // signer signs data hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            getEthSignedMessageHash(
                keccak256(
                    // create data hash
                    abi.encodePacked(
                        JOE,
                        claimData.amount,
                        currentIndex,
                        claimData.indexes,
                        block.timestamp
                    )
                )
            )
        );

        // claimWithSignature -> revert
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RevenueStreamETH.InvalidIndex.selector, JOE, currentIndex, 0));
        REV_STREAM.claimWithSignature(
            claimData.amount,
            currentIndex,
            claimData.indexes,
            block.timestamp,
            _packRsv(v, r, s)
        );
    }

    /// @dev Verifies a data discrepancy from the data that is signed will cause a revert.
    function test_revStreamETH_claimWithSignature_discrepancy_amount() public {
        ClaimData memory claimData;

        (claimData.amount, claimData.indexes) = REV_STREAM.claimable(JOE);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        bytes memory signature = _sign(JOE, claimData);

        // claimWithSignature with discrepancy -> revert
        vm.prank(JOE);
        vm.expectRevert();
        REV_STREAM.claimWithSignature(
            claimData.amount + 1, // discrepancy
            claimData.currentIndex,
            claimData.indexes,
            block.timestamp,
            signature
        );
    }

    /// @dev Verifies a data discrepancy from the data that is signed will cause a revert.
    function test_revStreamETH_claimWithSignature_discrepancy_currentIndex() public {
        ClaimData memory claimData;

        (claimData.amount, claimData.indexes) = REV_STREAM.claimable(JOE);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        bytes memory signature = _sign(JOE, claimData);

        // claimWithSignature with discrepancy -> revert
        vm.prank(JOE);
        vm.expectRevert();
        REV_STREAM.claimWithSignature(
            claimData.amount,
            claimData.currentIndex + 1, // discrepancy
            claimData.indexes,
            block.timestamp,
            signature
        );
    }

    /// @dev Verifies a data discrepancy from the data that is signed will cause a revert.
    function test_revStreamETH_claimWithSignature_discrepancy_indexes() public {
        ClaimData memory claimData;

        (claimData.amount, claimData.indexes) = REV_STREAM.claimable(JOE);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        bytes memory signature = _sign(JOE, claimData);

        // claimWithSignature with discrepancy -> revert
        vm.prank(JOE);
        vm.expectRevert();
        REV_STREAM.claimWithSignature(
            claimData.amount,
            claimData.currentIndex,
            claimData.indexes + 1, // discrepancy
            block.timestamp,
            signature
        );
    }

    /// @dev Verifies using an expired signature will cause a revert.
    function test_revStreamETH_claimWithSignature_expiredSignature() public {
        ClaimData memory claimData;

        (claimData.amount, claimData.indexes) = REV_STREAM.claimable(JOE);
        claimData.currentIndex = REV_STREAM.lastClaimIndex(JOE);

        bytes memory signature = _sign(JOE, claimData);

        uint256 deadline = block.timestamp;
        skip(2);

        // claimWithSignature with discrepancy -> revert
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RevenueStreamETH.SignatureExpired.selector, block.timestamp, deadline));
        REV_STREAM.claimWithSignature(
            claimData.amount,
            claimData.currentIndex,
            claimData.indexes,
            deadline, // expired
            signature
        );
    }
}