// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { OFTCoreUpgradeable, OFTUpgradeable } from "@tangible-foundation-contracts/layerzero/token/oft/v1/OFTUpgradeable.sol";
import { CrossChainToken } from "@tangible-foundation-contracts/tokens/CrossChainToken.sol";
import { IOFTCore } from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";
import { BytesLib } from "@layerzerolabs/contracts/libraries/BytesLib.sol";

/**
 * @title WrappedstRWASatellite
 * @notice Staked RWA Satellite Token allowing for cross-chain bridging of the 'stRWA' token.
 */
contract WrappedstRWASatellite is UUPSUpgradeable, CrossChainToken, OFTUpgradeable {
    using BytesLib for bytes;

    // ~ Constructor ~

    /**
     * @notice Initializes WrappedstRWASatellite.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     */
    constructor(uint256 mainChainId, address lzEndpoint)
        OFTUpgradeable(lzEndpoint)
        CrossChainToken(mainChainId)
    {
        _disableInitializers();
    }


    // ~ Initializer ~

    /**
     * @notice Initializes WrappedstRWASatellite's inherited upgradeables.
     * @param owner Initial owner of contract.
     * @param name Name of wrapped token.
     * @param symbol Symbol of wrapped token.
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol
    ) external initializer {
        __OFT_init(owner, name, symbol);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // ~ LayerZero overrides ~

    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes calldata _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) public payable override(IOFTCore, OFTCoreUpgradeable) {
        _send(
            _from,
            _dstChainId,
            _toAddress,
            _amount,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    /**
     * @notice Initiates the sending of tokens to another chain.
     * @dev This function prepares a message containing the shares. It then uses LayerZero's send functionality
     * to send the tokens to the destination chain. The function checks adapter parameters and emits
     * a `SendToChain` event upon successful execution.
     *
     * @param from The address from which tokens are sent.
     * @param dstChainId The destination chain ID.
     * @param toAddress The address on the destination chain to which tokens will be sent.
     * @param amount The amount of tokens to send.
     * @param refundAddress The address for any refunds.
     * @param zroPaymentAddress The address for ZRO payment.
     * @param adapterParams Additional parameters for the adapter.
     */
    function _send(
        address from,
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) internal override {

        _checkAdapterParams(dstChainId, PT_SEND, adapterParams, NO_EXTRA_GAS);

        amount = _debitFrom(from, dstChainId, toAddress, amount);

        emit SendToChain(dstChainId, from, toAddress, amount);

        bytes memory lzPayload = abi.encode(PT_SEND, msg.sender, from, toAddress, amount);
        _lzSend(dstChainId, lzPayload, refundAddress, zroPaymentAddress, adapterParams, msg.value);
    }

    /**
     * @notice Acknowledges the receipt of tokens from another chain and credits the correct amount to the recipient's
     * address.
     * @dev Upon receiving a payload, this function decodes it to extract the destination address and the message
     * content, which includes shares to credit an account.
     *
     * @param srcChainId The source chain ID from which tokens are received.
     * @param srcAddressBytes The address on the source chain from which the message originated.
     * @param payload The payload containing the encoded destination address and message with shares.
     */
    function _sendAck(uint16 srcChainId, bytes memory srcAddressBytes, uint64, bytes memory payload)
        internal
        override
    {
        (, address initiator, address from, bytes memory toAddressBytes, uint256 shares) =
            abi.decode(payload, (uint16, address, address, bytes, uint256));

        address src = srcAddressBytes.toAddress(0);
        address to = toAddressBytes.toAddress(0);
        uint256 amount;

        amount = _creditTo(srcChainId, to, shares);

        _tryNotifyReceiver(srcChainId, initiator, from, src, to, amount);

        emit ReceiveFromChain(srcChainId, to, amount);
    }
}