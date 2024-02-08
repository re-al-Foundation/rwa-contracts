// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// tangible imports
import { NonblockingLzAppUpgradeable } from "@tangible-foundation-contracts/layerzero/lzApp/NonblockingLzAppUpgradeable.sol";

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
contract RealReceiver is NonblockingLzAppUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
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

    // ------
    // Errors
    // ------

    /**
     * @notice This error is emitted when there's a failed migration or mint message.
     * @dev This is emitted if the message to veRwaNFT or rwaToken to complete migration or mint fails.
     * @param packetType Type of migration that fails; NFT, Batch NFT, or ERC-20 token.
     */
    error MigrationFailed(uint16 packetType);

    
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
        veRwaNFT = _veRwaNFT;
        rwaToken = _rwaToken;
        srcChainId = _srcChainId;

        __NonblockingLzApp_init(_admin);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows a permissioned admin to update the `veRwaNFT` address.
     * @param _newVeRwa New address.
     */
    function setVotingEscrowRWA(address _newVeRwa) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newVeRwa != address(0), "Cannot be address(0)");
        veRwaNFT = _newVeRwa;
    }

    /**
     * @notice This method allows a permissioned admin to update the `rwaToken` address.
     * @param _newRwaToken New address.
     */
    function setRwaToken(address _newRwaToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newRwaToken != address(0), "Cannot be address(0)");
        rwaToken = _newRwaToken;
    }

    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Handles incoming cross-chain messages and executes corresponding actions.
     * @dev This function is an override of the `_nonblockingLzReceive` function from the NonblockingLzAppUpgradeable contract. 
     * It processes incoming messages from LayerZero's cross-chain communication.
     * @param srcChainId The source chain ID from which the message is sent.
     * @param srcAddress The source address in the originating chain, encoded in bytes.
     * @param nonce A unique identifier for the message.
     * @param payload The payload of the message, containing the data necessary for processing.
     */
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal virtual override {
        uint16 packetType;

        assembly {
            packetType := mload(add(payload, 32))
        }

        if (packetType == SEND_NFT) _migrateNFT(payload);
        else if (packetType == SEND_NFT_BATCH) _migrateNFTBatch(payload);
        else _migrateTokens(payload);
    }

    /**
     * @notice Internal method for handling migration payloads for migrating to a veRWA NFT.
     * @param payload Payload containing NFT lock data.
     */
    function _migrateNFT(bytes memory payload) internal {
        (, bytes memory toAddressBytes, uint256 amount, uint256 duration) =
            abi.decode(payload, (uint16, bytes, uint256, uint256));

        address to = toAddressBytes.toAddress(0);

        (bool success,) = address(veRwaNFT).call(
            abi.encodeWithSignature("migrate(address,uint256,uint256)", to, amount, duration)
        );
        if (!success) revert MigrationFailed(SEND_NFT);

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

        (bool success,) = address(veRwaNFT).call(
            abi.encodeWithSignature("migrateBatch(address,uint256[],uint256[])", to, amounts, durations)
        );
        if (!success) revert MigrationFailed(SEND_NFT_BATCH);

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

        (bool success,) = address(rwaToken).call(
            abi.encodeWithSignature("mintFor(address,uint256)", to, amount)
        );
        if (!success) revert MigrationFailed(SEND);

        emit MigrationMessageReceived(SEND, to, payload);
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the DEFAULT_ADMIN_ROLE role to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}