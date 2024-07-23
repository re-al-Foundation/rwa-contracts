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
    address public constant DELEGATOR_ADMIN = 0x946C569791De3283f33372731d77555083c329da;

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 184960);

        // upgrade RevenueStreamETH -> gives us claimWithSignature
        vm.startPrank(DELEGATOR_ADMIN);
        RevenueStreamETH newRevStream = new RevenueStreamETH();
        REV_STREAM.upgradeToAndCall(address(newRevStream), "");
        vm.stopPrank();
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

    function testSignature1() public {
        uint256 privateKey = 123;
        // Computes the address for a given private key.
        address alice = vm.addr(privateKey);

        // Test valid signature
        bytes32 messageHash = keccak256("Signed by Alice");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        address signer = ecrecover(messageHash, v, r, s);

        assertEq(signer, alice);
    }

    function testSignature2() public {
        uint256 privateKey = 123;
        address signer = vm.addr(privateKey);
        emit log_named_address("signer", signer);

        address account = JOE;
        uint256 amount = 1 ether;
        uint256 currentIndex = 0;
        uint256 newIndex = 1455;

        bytes32 data = keccak256(abi.encodePacked(account, amount, currentIndex, newIndex));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, data);

        claimSignature(account, amount, currentIndex, newIndex, _packRsv(v, r, s));

    }

    function claimSignature(address account, uint256 amount, uint256 currentIndex, uint256 newIndex, bytes memory signature) internal {
        // create the hash from data
        emit log_named_bytes("sig", signature);
        // use hash + signature to verify signer address
        bytes32 data = keccak256(abi.encodePacked(account, amount, currentIndex, newIndex));

        address signer = ECDSA.recover(data, signature);
        emit log_named_address("signer", signer);
    }
}