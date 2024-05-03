// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// tangible imports
import { NonblockingLzAppUpgradeable } from "@tangible-foundation-contracts/layerzero/lzApp/NonblockingLzAppUpgradeable.sol";

// local imports
import { IRWAToken } from "./interfaces/IRWAToken.sol";
import { IRWAVotingEscrow } from "./interfaces/IRWAVotingEscrow.sol";

// LayerZero imports
import { BytesLib } from "./libraries/BytesLib.sol";

/**
 * @title RealReceiver
 * @author @chasebrownn
 * @notice This contract inherits `ILayerZeroReceiver` and facilitates the migration message from the source on Polygon
 *         to the migration method on the destination contract. This contract specifically handles the migration messages for veRWA.
 *
 * Key Features:
 * - Can receive a message from the local LayerZero endpoint.
 * - During a migration process, will receive the message from CrossChainMigrator on Polygon to fulfill an NFT migration.
 *   Will take the data payload and use it to call the VotingEscrowRWA contract.
 */
contract RealReceiver is OwnableUpgradeable, NonblockingLzAppUpgradeable, UUPSUpgradeable {
    using BytesLib for bytes;

    // ---------------
    // State Variables
    // ---------------

    /// @notice Packet type for ERC-20 token migration message.
    uint16 private constant SEND = 0;
    /// @notice Packet type for NFT migration message.
    uint16 private constant SEND_NFT = 1;
    /// @notice Packet type for NFT batch migration message.
    uint16 private constant SEND_NFT_BATCH = 2;
    /// @notice Destination contract address for veRWA NFT contract on REAL.
    address public veRwaNFT;
    /// @notice Destination contract address for RWA token contract on REAL.
    address public rwaToken;
    /// @notice Chain Id of source chain. In our case, Polygon -> 137
    uint16 public srcChainId;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when a successful execution of `lzReceive` occurs.
     * @param packetType Migration type.
     * @param migrator EOA that is migrating. Receiver of migrated token(s).
     * @param _payload Migration data received from endpoint.
     */
    event MigrationMessageReceived(uint16 packetType, address migrator, bytes _payload);

    /**
     * @notice This event is emitted when a new `votingEscrowRWA` is set.
     * @param newRWAVotingEscrow New address stored in `votingEscrowRWA`.
     */
    event RWAVotingEscrowSet(address indexed newRWAVotingEscrow);

    /**
     * @notice This event is emitted when a new `rwaToken` is set.
     * @param newRWAToken New value stored in `rwaToken`.
     */
    event RWATokenSet(address indexed newRWAToken);

    // ------
    // Errors
    // ------

    /**
     * @notice This error is emitted when there's an invalid packet type that is received.
     * @param packetType packet type that was received and deemed invalid. 
     */
    error InvalidPacketType(uint16 packetType);

    
    // -----------
    // Constructor
    // -----------

    /**
     * @param lzEndpoint Local Layer Zero endpoint.
     */
    constructor(address lzEndpoint) NonblockingLzAppUpgradeable(lzEndpoint) {}


    // -----------
    // Initializer
    // -----------

    /**
     * @notice This method initializes the RealReceiver contract.
     * @param _srcChainId Chain Id of source chain. In our case, Polygon.
     * @param _veRwaNFT Contract address of VotingEscrowRWA.
     * @param _rwaToken Contract address of RWAToken.
     * @param _admin Admin address.
     */
    function initialize(
        uint16 _srcChainId,
        address _veRwaNFT,
        address _rwaToken,
        address _admin
    ) external initializer {
        require(_admin != address(0));
        require(_srcChainId != uint16(0));

        __Ownable_init(_admin);
        __NonblockingLzApp_init(_admin);
        __UUPSUpgradeable_init();
        
        veRwaNFT = _veRwaNFT;
        rwaToken = _rwaToken;
        srcChainId = _srcChainId;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows a permissioned admin to update the `veRwaNFT` address.
     * @param _newVeRwa New address.
     */
    function setVotingEscrowRWA(address _newVeRwa) external onlyOwner {
        require(_newVeRwa != address(0), "Cannot be address(0)");
        emit RWAVotingEscrowSet(_newVeRwa);
        veRwaNFT = _newVeRwa;
    }

    /**
     * @notice This method allows a permissioned admin to update the `rwaToken` address.
     * @param _newRwaToken New address.
     */
    function setRwaToken(address _newRwaToken) external onlyOwner {
        require(_newRwaToken != address(0), "Cannot be address(0)");
        emit RWATokenSet(_newRwaToken);
        rwaToken = _newRwaToken;
    }

    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Handles incoming cross-chain messages and executes corresponding actions.
     * @dev This function is an override of the `_nonblockingLzReceive` function from the NonblockingLzAppUpgradeable contract. 
     * It processes incoming messages from LayerZero's cross-chain communication.
     * @param payload The payload of the message, containing the data necessary for processing.
     */
    function _nonblockingLzReceive(
        uint16 /**  srcChainId */,
        bytes memory /** srcAddress */,
        uint64 /** nonce */,
        bytes memory payload
    ) internal virtual override {
        uint16 packetType;

        assembly {
            packetType := mload(add(payload, 32))
        }

        if (packetType == SEND_NFT) _migrateNFT(payload);
        else if (packetType == SEND_NFT_BATCH) _migrateNFTBatch(payload);
        else if (packetType == SEND) _migrateTokens(payload);
        else revert InvalidPacketType(packetType);
    }

    /**
     * @notice Internal method for handling migration payloads for migrating to a veRWA NFT.
     * @param payload Payload containing NFT lock data.
     */
    function _migrateNFT(bytes memory payload) internal {
        (, bytes memory toAddressBytes, uint256 amount, uint256 duration) =
            abi.decode(payload, (uint16, bytes, uint256, uint256));

        address to = toAddressBytes.toAddress(0);
        IRWAVotingEscrow(address(veRwaNFT)).migrate(to, amount, duration);

        emit MigrationMessageReceived(SEND_NFT, to, payload);
    }

    /**
     * @notice Internal method for handling migration payloads for migrating a batch of veRWA NFTs.
     * @param payload Payload containing NFT lock data.
     */
    function _migrateNFTBatch(bytes memory payload) internal {
        (, bytes memory toAddressBytes, uint256[] memory amounts, uint256[] memory durations) =
            abi.decode(payload, (uint16, bytes, uint256[], uint256[]));

        address to = toAddressBytes.toAddress(0);
        IRWAVotingEscrow(address(veRwaNFT)).migrateBatch(to, amounts, durations);

        emit MigrationMessageReceived(SEND_NFT_BATCH, to, payload);
    }

    /**
     * @notice Internal method for handling migration payloads for migrating to $RWA tokens.
     * @param payload Payload migration data.
     */
    function _migrateTokens(bytes memory payload) internal {
        (, bytes memory toAddressBytes, uint256 amount) =
            abi.decode(payload, (uint16, bytes, uint256));

        address to = toAddressBytes.toAddress(0);
        IRWAToken(address(rwaToken)).mintFor(to, amount);

        emit MigrationMessageReceived(SEND, to, payload);
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the DEFAULT_ADMIN_ROLE role to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}