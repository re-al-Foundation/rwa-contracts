// SPDX-License-Identifier: MIT
pragma solidity <0.9.0 >=0.5.0 >=0.7.6 >=0.8.0 ^0.8.20;

// lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/libraries/BytesLib.sol

/*
 * @title Solidity Bytes Arrays Utils
 * @author Gonçalo Sá <goncalo.sa@consensys.net>
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */

library BytesLib {
    function concat(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bytes memory) {
        bytes memory tempBytes;

        assembly {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
            tempBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for tempBytes.
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(tempBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the _preBytes data,
                // 32 bytes into its memory.
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the _preBytes data into the tempBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of _postBytes to the current length of tempBytes
            // and store it as the new length in the first 32 bytes of the
            // tempBytes memory.
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the _preBytes data.
            mc := end
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of tempBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(
                0x40,
                and(
                    add(add(end, iszero(add(length, mload(_preBytes)))), 31),
                    not(31) // Round down to the nearest 32 bytes.
                )
            )
        }

        return tempBytes;
    }

    function concatStorage(bytes storage _preBytes, bytes memory _postBytes) internal {
        assembly {
            // Read the first 32 bytes of _preBytes storage, which is the length
            // of the array. (We don't need to use the offset into the slot
            // because arrays use the entire slot.)
            let fslot := sload(_preBytes.slot)
            // Arrays of 31 bytes or less have an even value in their slot,
            // while longer arrays have an odd value. The actual length is
            // the slot divided by two for odd values, and the lowest order
            // byte divided by two for even values.
            // If the slot is even, bitwise and the slot with 255 and divide by
            // two to get the length. If the slot is odd, bitwise and the slot
            // with -1 and divide by two.
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            // slength can contain both the length and contents of the array
            // if length < 32 bytes so let's prepare for that
            // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
            switch add(lt(slength, 32), lt(newlength, 32))
            case 2 {
                // Since the new array still fits in the slot, we just need to
                // update the contents of the slot.
                // uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                sstore(
                    _preBytes.slot,
                    // all the modifications to the slot are inside this
                    // next block
                    add(
                        // we can just add to the slot contents because the
                        // bytes we want to change are the LSBs
                        fslot,
                        add(
                            mul(
                                div(
                                    // load the bytes from memory
                                    mload(add(_postBytes, 0x20)),
                                    // zero all bytes to the right
                                    exp(0x100, sub(32, mlength))
                                ),
                                // and now shift left the number of bytes to
                                // leave space for the length in the slot
                                exp(0x100, sub(32, newlength))
                            ),
                            // increase length by the double of the memory
                            // bytes length
                            mul(mlength, 2)
                        )
                    )
                )
            }
            case 1 {
                // The stored value fits in the slot, but the combined value
                // will exceed it.
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes.slot)
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                // The contents of the _postBytes array start 32 bytes into
                // the structure. Our first read should obtain the `submod`
                // bytes that can fit into the unused space in the last word
                // of the stored array. To get this, we read 32 bytes starting
                // from `submod`, so the data we read overlaps with the array
                // contents by `submod` bytes. Masking the lowest-order
                // `submod` bytes allows us to add that value directly to the
                // stored value.

                let submod := sub(32, slength)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(and(fslot, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00), and(mload(mc), mask)))

                for {
                    mc := add(mc, 0x20)
                    sc := add(sc, 1)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
            default {
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes.slot)
                // Start copying to the last used word of the stored array.
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                // Copy over the first `submod` bytes of the new data as in
                // case 1 above.
                let slengthmod := mod(slength, 32)
                let mlengthmod := mod(mlength, 32)
                let submod := sub(32, slengthmod)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(sload(sc), and(mload(mc), mask)))

                for {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
        }
    }

    function slice(
        bytes memory _bytes,
        uint _start,
        uint _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint _start) internal pure returns (address) {
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint _start) internal pure returns (uint8) {
        require(_bytes.length >= _start + 1, "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(bytes memory _bytes, uint _start) internal pure returns (uint16) {
        require(_bytes.length >= _start + 2, "toUint16_outOfBounds");
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint32(bytes memory _bytes, uint _start) internal pure returns (uint32) {
        require(_bytes.length >= _start + 4, "toUint32_outOfBounds");
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint64(bytes memory _bytes, uint _start) internal pure returns (uint64) {
        require(_bytes.length >= _start + 8, "toUint64_outOfBounds");
        uint64 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x8), _start))
        }

        return tempUint;
    }

    function toUint96(bytes memory _bytes, uint _start) internal pure returns (uint96) {
        require(_bytes.length >= _start + 12, "toUint96_outOfBounds");
        uint96 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xc), _start))
        }

        return tempUint;
    }

    function toUint128(bytes memory _bytes, uint _start) internal pure returns (uint128) {
        require(_bytes.length >= _start + 16, "toUint128_outOfBounds");
        uint128 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x10), _start))
        }

        return tempUint;
    }

    function toUint256(bytes memory _bytes, uint _start) internal pure returns (uint) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(bytes memory _bytes, uint _start) internal pure returns (bytes32) {
        require(_bytes.length >= _start + 32, "toBytes32_outOfBounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        bool success = true;

        assembly {
            let length := mload(_preBytes)

            // if lengths don't match the arrays are not equal
            switch eq(length, mload(_postBytes))
            case 1 {
                // cb is a circuit breaker in the for loop since there's
                //  no said feature for inline assembly loops
                // cb = 1 - don't breaker
                // cb = 0 - break
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for {
                    let cc := add(_postBytes, 0x20)
                    // the next line is the loop condition:
                    // while(uint256(mc < end) + cb == 2)
                } eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // if any of these checks fails then arrays are not equal
                    if iszero(eq(mload(mc), mload(cc))) {
                        // unsuccess:
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }

    function equalStorage(bytes storage _preBytes, bytes memory _postBytes) internal view returns (bool) {
        bool success = true;

        assembly {
            // we know _preBytes_offset is 0
            let fslot := sload(_preBytes.slot)
            // Decode the length of the stored array like in concatStorage().
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)

            // if lengths don't match the arrays are not equal
            switch eq(slength, mlength)
            case 1 {
                // slength can contain both the length and contents of the array
                // if length < 32 bytes so let's prepare for that
                // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
                if iszero(iszero(slength)) {
                    switch lt(slength, 32)
                    case 1 {
                        // blank the last byte which is the length
                        fslot := mul(div(fslot, 0x100), 0x100)

                        if iszero(eq(fslot, mload(add(_postBytes, 0x20)))) {
                            // unsuccess:
                            success := 0
                        }
                    }
                    default {
                        // cb is a circuit breaker in the for loop since there's
                        //  no said feature for inline assembly loops
                        // cb = 1 - don't breaker
                        // cb = 0 - break
                        let cb := 1

                        // get the keccak hash to get the contents of the array
                        mstore(0x0, _preBytes.slot)
                        let sc := keccak256(0x0, 0x20)

                        let mc := add(_postBytes, 0x20)
                        let end := add(mc, mlength)

                        // the next line is the loop condition:
                        // while(uint256(mc < end) + cb == 2)
                        for {

                        } eq(add(lt(mc, end), cb), 2) {
                            sc := add(sc, 1)
                            mc := add(mc, 0x20)
                        } {
                            if iszero(eq(sload(sc), mload(mc))) {
                                // unsuccess:
                                success := 0
                                cb := 0
                            }
                        }
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }
}

// lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/libraries/ExcessivelySafeCall.sol

library ExcessivelySafeCall {
    uint constant LOW_28_MASK = 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// @notice Use when you _really_ really _really_ don't trust the called
    /// contract. This prevents the called contract from causing reversion of
    /// the caller in as many ways as we can.
    /// @dev The main difference between this and a solidity low-level call is
    /// that we limit the number of bytes that the callee can cause to be
    /// copied to caller memory. This prevents stupid things like malicious
    /// contracts returning 10,000,000 bytes causing a local OOG when copying
    /// to memory.
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function excessivelySafeCall(
        address _target,
        uint _gas,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal returns (bool, bytes memory) {
        // set up for assembly call
        uint _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := call(
                _gas, // gas
                _target, // recipient
                0, // ether value
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /// @notice Use when you _really_ really _really_ don't trust the called
    /// contract. This prevents the called contract from causing reversion of
    /// the caller in as many ways as we can.
    /// @dev The main difference between this and a solidity low-level call is
    /// that we limit the number of bytes that the callee can cause to be
    /// copied to caller memory. This prevents stupid things like malicious
    /// contracts returning 10,000,000 bytes causing a local OOG when copying
    /// to memory.
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function excessivelySafeStaticCall(
        address _target,
        uint _gas,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal view returns (bool, bytes memory) {
        // set up for assembly call
        uint _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := staticcall(
                _gas, // gas
                _target, // recipient
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /**
     * @notice Swaps function selectors in encoded contract calls
     * @dev Allows reuse of encoded calldata for functions with identical
     * argument types but different names. It simply swaps out the first 4 bytes
     * for the new selector. This function modifies memory in place, and should
     * only be used with caution.
     * @param _newSelector The new 4-byte selector
     * @param _buf The encoded contract args
     */
    function swapSelector(bytes4 _newSelector, bytes memory _buf) internal pure {
        require(_buf.length >= 4);
        uint _mask = LOW_28_MASK;
        assembly {
            // load the first word of
            let _word := mload(add(_buf, 0x20))
            // mask out the top 4 bytes
            // /x
            _word := and(_word, _mask)
            _word := or(_newSelector, _word)
            mstore(add(_buf, 0x20), _word)
        }
    }
}

// lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/interfaces/ILayerZeroReceiver.sol

interface ILayerZeroReceiver {
    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external;
}

// lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/interfaces/ILayerZeroUserApplicationConfig.sol

interface ILayerZeroUserApplicationConfig {
    // @notice set the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _configType - type of configuration. every messaging library has its own convention.
    // @param _config - configuration in the bytes. can encode arbitrary content.
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external;

    // @notice set the send() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setSendVersion(uint16 _version) external;

    // @notice set the lzReceive() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setReceiveVersion(uint16 _version) external;

    // @notice Only when the UA needs to resume the message flow in blocking mode and clear the stored payload
    // @param _srcChainId - the chainId of the source chain
    // @param _srcAddress - the contract address of the source contract at the source chain
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external;
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reininitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        assembly {
            $.slot := INITIALIZABLE_STORAGE
        }
    }
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC1822.sol

// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/draft-IERC1822.sol)

/**
 * @dev ERC1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
 * proxy whose upgrades are fully controlled by the current implementation.
 */
interface IERC1822Proxiable {
    /**
     * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
     * address.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy.
     */
    function proxiableUUID() external view returns (bytes32);
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol

// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/draft-IERC6093.sol)

/**
 * @dev Standard ERC20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC20 tokens.
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Standard ERC721 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC721 tokens.
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in EIP-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC721InvalidOperator(address operator);
}

/**
 * @dev Standard ERC1155 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC1155 tokens.
 */
interface IERC1155Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     * @param tokenId Identifier number of a token.
     */
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC1155InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC1155InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param owner Address of the current owner of a token.
     */
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC1155InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC1155InvalidOperator(address operator);

    /**
     * @dev Indicates an array length mismatch between ids and values in a safeBatchTransferFrom operation.
     * Used in batch transfers.
     * @param idsLength Length of the array of token identifiers
     * @param valuesLength Length of the array of token amounts
     */
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/beacon/IBeacon.sol)

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/tangible-foundation-contracts/src/layerzero/token/oft/interfaces/IOFTSubscriber.sol

/**
 * @dev Interface of the OFT subscriber
 */
interface IOFTSubscriber {
    /**
     * @notice Notifies the contract about a token credit from a source chain.
     * @dev This function allows external systems to inform the contract about credited tokens.
     * @param srcChainId Chain ID of the source chain.
     * @param token Address of the credited token.
     * @param src Address of the sender on the source chain.
     * @param amount Amount of tokens credited.
     */
    function notifyCredit(uint16 srcChainId, address token, address src, uint256 amount) external;
}

// lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/interfaces/ILayerZeroEndpoint.sol

interface ILayerZeroEndpoint is ILayerZeroUserApplicationConfig {
    // @notice send a LayerZero message to the specified address at a LayerZero endpoint.
    // @param _dstChainId - the destination chain identifier
    // @param _destination - the address on destination chain (in bytes). address length/format may vary by chains
    // @param _payload - a custom bytes payload to send to the destination contract
    // @param _refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
    // @param _zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
    // @param _adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;

    // @notice used by the messaging library to publish verified payload
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source contract (as bytes) at the source chain
    // @param _dstAddress - the address on destination chain
    // @param _nonce - the unbound message ordering nonce
    // @param _gasLimit - the gas limit for external contract execution
    // @param _payload - verified payload to send to the destination contract
    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint _gasLimit,
        bytes calldata _payload
    ) external;

    // @notice get the inboundNonce of a lzApp from a source chain which could be EVM or non-EVM chain
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (uint64);

    // @notice get the outboundNonce from this source chain which, consequently, is always an EVM
    // @param _srcAddress - the source chain contract address
    function getOutboundNonce(uint16 _dstChainId, address _srcAddress) external view returns (uint64);

    // @notice gets a quote in source native gas, for the amount that send() requires to pay for message delivery
    // @param _dstChainId - the destination chain identifier
    // @param _userApplication - the user app address on this EVM chain
    // @param _payload - the custom message to send over LayerZero
    // @param _payInZRO - if false, user app pays the protocol fee in native token
    // @param _adapterParam - parameters for the adapter service, e.g. send some dust native token to dstChain
    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint nativeFee, uint zroFee);

    // @notice get this Endpoint's immutable source identifier
    function getChainId() external view returns (uint16);

    // @notice the interface to retry failed message on this Endpoint destination
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    // @param _payload - the payload to be retried
    function retryPayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        bytes calldata _payload
    ) external;

    // @notice query if any STORED payload (message blocking) at the endpoint.
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool);

    // @notice query if the _libraryAddress is valid for sending msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getSendLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the _libraryAddress is valid for receiving msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getReceiveLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the non-reentrancy guard for send() is on
    // @return true if the guard is on. false otherwise
    function isSendingPayload() external view returns (bool);

    // @notice query if the non-reentrancy guard for receive() is on
    // @return true if the guard is on. false otherwise
    function isReceivingPayload() external view returns (bool);

    // @notice get the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _userApplication - the contract address of the user application
    // @param _configType - type of configuration. every messaging library has its own convention.
    function getConfig(
        uint16 _version,
        uint16 _chainId,
        address _userApplication,
        uint _configType
    ) external view returns (bytes memory);

    // @notice get the send() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getSendVersion(address _userApplication) external view returns (uint16);

    // @notice get the lzReceive() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getReceiveVersion(address _userApplication) external view returns (uint16);
}

// lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol

/**
 * @dev Interface of the IOFT core standard
 */
interface IOFTCore is IERC165 {
    /**
     * @dev estimate send token `_tokenId` to (`_dstChainId`, `_toAddress`)
     * _dstChainId - L0 defined chain id to send tokens too
     * _toAddress - dynamic bytes array which contains the address to whom you are sending tokens to on the dstChain
     * _amount - amount of the tokens to transfer
     * _useZro - indicates to use zro to pay L0 fees
     * _adapterParam - flexible bytes array to indicate messaging adapter services in L0
     */
    function estimateSendFee(uint16 _dstChainId, bytes calldata _toAddress, uint _amount, bool _useZro, bytes calldata _adapterParams) external view returns (uint nativeFee, uint zroFee);

    /**
     * @dev send `_amount` amount of token to (`_dstChainId`, `_toAddress`) from `_from`
     * `_from` the owner of token
     * `_dstChainId` the destination chain identifier
     * `_toAddress` can be any size depending on the `dstChainId`.
     * `_amount` the quantity of tokens in wei
     * `_refundAddress` the address LayerZero refunds if too much message fee is sent
     * `_zroPaymentAddress` set to address(0x0) if not paying in ZRO (LayerZero Token)
     * `_adapterParams` is a flexible bytes array to indicate messaging adapter services
     */
    function sendFrom(address _from, uint16 _dstChainId, bytes calldata _toAddress, uint _amount, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external payable;

    /**
     * @dev returns the circulating amount of tokens on current chain
     */
    function circulatingSupply() external view returns (uint);

    /**
     * @dev returns the address of the ERC20 token
     */
    function token() external view returns (address);

    /**
     * @dev Emitted when `_amount` tokens are moved from the `_sender` to (`_dstChainId`, `_toAddress`)
     * `_nonce` is the outbound nonce
     */
    event SendToChain(uint16 indexed _dstChainId, address indexed _from, bytes _toAddress, uint _amount);

    /**
     * @dev Emitted when `_amount` tokens are received from `_srcChainId` into the `_toAddress` on the local chain.
     * `_nonce` is the inbound nonce.
     */
    event ReceiveFromChain(uint16 indexed _srcChainId, address indexed _to, uint _amount);

    event SetUseCustomAdapterParams(bool _useCustomAdapterParams);
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Metadata.sol)

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/introspection/ERC165.sol)

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OwnableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OwnableStorageLocation
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/token/oft/v1/interfaces/IOFT.sol

/**
 * @dev Interface of the OFT standard
 */
interface IOFT is IOFTCore, IERC20 {

}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/ERC1967/ERC1967Utils.sol)

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 */
library ERC1967Utils {
    // We re-declare ERC-1967 events here because they can't be used directly from IERC1967.
    // This will be fixed in Solidity 0.8.21. At that point we should remove these events.
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/ERC20.sol)

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * The default value of {decimals} is 18. To change this, you should override
 * this function so it returns a different value.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 */
abstract contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20, IERC20Metadata, IERC20Errors {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20
    struct ERC20Storage {
        mapping(address account => uint256) _balances;

        mapping(address account => mapping(address spender => uint256)) _allowances;

        uint256 _totalSupply;

        string _name;
        string _symbol;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function _getERC20Storage() private pure returns (ERC20Storage storage $) {
        assembly {
            $.slot := ERC20StorageLocation
        }
    }

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing {
        ERC20Storage storage $ = _getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `value`.
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `value`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `value`.
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        ERC20Storage storage $ = _getERC20Storage();
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            $._totalSupply += value;
        } else {
            uint256 fromBalance = $._balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                $._balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                $._totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                $._balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, lowering the total supply.
     * Relies on the `_update` mechanism.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead
     */
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /**
     * @dev Sets `value` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     * ```
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        ERC20Storage storage $ = _getERC20Storage();
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        $._allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

// lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/UUPSUpgradeable.sol)

/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
 */
abstract contract UUPSUpgradeable is IERC1822Proxiable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable __self = address(this);

    /**
     * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgradeTo(address)`
     * and `upgradeToAndCall(address,bytes)` are present, and `upgradeTo` must be used if no function should be called,
     * while `upgradeToAndCall` will invoke the `receive` function if the second argument is the empty byte string.
     * If the getter returns `"5.0.0"`, only `upgradeToAndCall(address,bytes)` is present, and the second argument must
     * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
     * during an upgrade.
     */
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /**
     * @dev The call is from an unauthorized context.
     */
    error UUPSUnauthorizedCallContext();

    /**
     * @dev The storage `slot` is unsupported as a UUID.
     */
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    /**
     * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
     * callable on the implementing contract but not through proxies.
     */
    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    /**
     * @dev Implementation of the ERC1822 {proxiableUUID} function. This returns the storage slot used by the
     * implementation. It is used to validate the implementation's compatibility when performing an upgrade.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
     */
    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     *
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    /**
     * @dev Reverts if the execution is not performed via delegatecall or the execution
     * context is not of a proxy with an ERC1967-compliant implementation pointing to self.
     * See {_onlyProxy}.
     */
    function _checkProxy() internal view virtual {
        if (
            address(this) == __self || // Must be called through delegatecall
            ERC1967Utils.getImplementation() != __self // Must be called through an active proxy
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Reverts if the execution is performed via delegatecall.
     * See {notDelegated}.
     */
    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            // Must not be called through delegatecall
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /**
     * @dev Performs an implementation upgrade with a security check for UUPS proxies, and additional setup call.
     *
     * As a security check, {proxiableUUID} is invoked in the new implementation, and the return value
     * is expected to be the implementation slot in ERC1967.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert UUPSUnsupportedProxiableUUID(slot);
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } catch {
            // The implementation is not UUPS
            revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
        }
    }
}

// lib/tangible-foundation-contracts/src/layerzero/lzApp/LzAppUpgradeable.sol

/**
 * @title LzAppUpgradeable
 * @dev This is a generic implementation of LzReceiver, designed for LayerZero cross-chain communication.
 *
 * The contract inherits from `OwnableUpgradeable` and implements `ILayerZeroReceiver` and
 * `ILayerZeroUserApplicationConfig` interfaces. It provides functionality for setting and managing trusted remote
 * chains and their corresponding paths, configuring minimum destination gas, payload size limitations, and more.
 *
 * The contract uses a custom storage location `LzAppStorage`, which includes various mappings and state variables such
 * as `trustedRemoteLookup`, `minDstGasLookup`, and `payloadSizeLimitLookup`.
 *
 * Events:
 * - `SetPrecrime(address)`: Emitted when the precrime address is set.
 * - `SetTrustedRemote(uint16, bytes)`: Emitted when a trusted remote chain is set with its path.
 * - `SetTrustedRemoteAddress(uint16, bytes)`: Emitted when a trusted remote chain is set with its address.
 * - `SetMinDstGas(uint16, uint16, uint256)`: Emitted when minimum destination gas is set for a chain and packet type.
 *
 * Initialization:
 * The contract should be initialized by calling `__LzApp_init` function.
 *
 * Permissions:
 * Most administrative tasks require the sender to be the contract's owner.
 *
 * Note:
 * The contract includes the Checks-Effects-Interactions pattern and optimizes for gas-efficiency wherever applicable.
 */
abstract contract LzAppUpgradeable is OwnableUpgradeable, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    using BytesLib for bytes;

    // ua can not send payload larger than this by default, but it can be changed by the ua owner
    uint256 public constant DEFAULT_PAYLOAD_SIZE_LIMIT = 10_000;

    event SetPrecrime(address precrime);
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
    event SetTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);
    event SetMinDstGas(uint16 _dstChainId, uint16 _type, uint256 _minDstGas);

    /// @custom:storage-location erc7201:layerzero.storage.LzApp
    struct LzAppStorage {
        mapping(uint16 => bytes) trustedRemoteLookup;
        mapping(uint16 => mapping(uint16 => uint256)) minDstGasLookup;
        mapping(uint16 => uint256) payloadSizeLimitLookup;
        address precrime;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.LzApp")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LzAppStorageLocation = 0x111388274dd962a0529050efb131321f60015c2ab1a99387d94540f430037b00;

    function _getLzAppStorage() private pure returns (LzAppStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := LzAppStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILayerZeroEndpoint public immutable lzEndpoint;

    /**
     * @param endpoint Address of the LayerZero endpoint contract.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) {
        lzEndpoint = ILayerZeroEndpoint(endpoint);
    }

    /**
     * @dev Initializes the contract with the given `initialOwner`.
     *
     * Requirements:
     * - The function should only be called during the initialization process.
     *
     * @param initialOwner Address of the initial owner of the contract.
     */
    function __LzApp_init(address initialOwner) internal onlyInitializing {
        __LzApp_init_unchained();
        __Ownable_init(initialOwner);
    }

    function __LzApp_init_unchained() internal onlyInitializing {}

    /**
     * @dev Returns the trusted path for a given remote chain ID.
     *
     * @param remoteChainId The ID of the remote chain to query for a trusted path.
     * @return path Bytes representation of the trusted path for the specified remote chain ID.
     */
    function trustedRemoteLookup(uint16 remoteChainId) external view returns (bytes memory path) {
        LzAppStorage storage $ = _getLzAppStorage();
        path = $.trustedRemoteLookup[remoteChainId];
    }

    /**
     * @dev Returns the minimum gas required for a given destination chain ID and packet type.
     *
     * @param dstChainId The ID of the destination chain to query for a minimum gas limit.
     * @param packetType The type of packet for which the minimum gas limit is to be fetched.
     * @return minGas The minimum gas limit required for the specified destination chain ID and packet type.
     */
    function minDstGasLookup(uint16 dstChainId, uint16 packetType) external view returns (uint256 minGas) {
        LzAppStorage storage $ = _getLzAppStorage();
        minGas = $.minDstGasLookup[dstChainId][packetType];
    }

    /**
     * @dev Returns the payload size limit for a given destination chain ID.
     *
     * @param dstChainId The ID of the destination chain to query for a payload size limit.
     * @return size The maximum allowable payload size in bytes for the specified destination chain ID.
     */
    function payloadSizeLimitLookup(uint16 dstChainId) external view returns (uint256 size) {
        LzAppStorage storage $ = _getLzAppStorage();
        size = $.payloadSizeLimitLookup[dstChainId];
    }

    /**
     * @dev Returns the address of the precrime contract.
     *
     * @return _precrime The address of the precrime contract.
     */
    function precrime() external view returns (address _precrime) {
        LzAppStorage storage $ = _getLzAppStorage();
        _precrime = $.precrime;
    }

    /**
     * @dev Handles incoming LayerZero messages from a source chain.
     * This function must be called by the LayerZero endpoint and validates the source of the message.
     *
     * Requirements:
     * - Caller must be the LayerZero endpoint.
     * - Source address must be a trusted remote address.
     *
     * @param srcChainId The ID of the source chain from which the message is sent.
     * @param srcAddress The address on the source chain that is sending the message.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data payload of the message.
     */
    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        public
        virtual
        override
    {
        LzAppStorage storage $ = _getLzAppStorage();

        // lzReceive must be called by the endpoint for security
        require(_msgSender() == address(lzEndpoint), "LzApp: invalid endpoint caller");

        bytes memory trustedRemote = $.trustedRemoteLookup[srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from
        // untrusted remote.
        require(
            srcAddress.length == trustedRemote.length && trustedRemote.length != 0
                && keccak256(srcAddress) == keccak256(trustedRemote),
            "LzApp: invalid source sending contract"
        );

        _blockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    /**
     * @dev Internal function that handles incoming LayerZero messages in a blocking manner.
     * This is an abstract function and should be implemented by derived contracts.
     *
     * @param srcChainId The ID of the source chain from which the message is sent.
     * @param srcAddress The address on the source chain that is sending the message.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data payload of the message.
     */
    function _blockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual;

    /**
     * @dev Internal function to send a LayerZero message to a destination chain.
     * It performs a series of validations before sending the message.
     *
     * Requirements:
     * - Destination chain must be a trusted remote.
     * - Payload size must be within the configured limit.
     *
     * @param dstChainId The ID of the destination chain.
     * @param payload The actual data payload to be sent.
     * @param refundAddress The address to which any refunds should be sent.
     * @param zroPaymentAddress The address for the ZRO token payment.
     * @param adapterParams Additional parameters required for the adapter.
     * @param nativeFee The native fee to be sent along with the message.
     */
    function _lzSend(
        uint16 dstChainId,
        bytes memory payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams,
        uint256 nativeFee
    ) internal virtual {
        LzAppStorage storage $ = _getLzAppStorage();
        bytes memory trustedRemote = $.trustedRemoteLookup[dstChainId];
        require(trustedRemote.length != 0, "LzApp: destination chain is not a trusted source");
        _checkPayloadSize(dstChainId, payload.length);
        lzEndpoint.send{value: nativeFee}(
            dstChainId, trustedRemote, payload, refundAddress, zroPaymentAddress, adapterParams
        );
    }

    /**
     * @dev Internal function to validate if the provided gas limit meets the minimum requirement for a given packet
     * type and destination chain.
     *
     * Requirements:
     * - The minimum destination gas limit must be set for the given packet type and destination chain.
     * - Provided gas limit should be greater than or equal to the sum of the minimum gas limit and any extra gas.
     *
     * @param dstChainId The ID of the destination chain.
     * @param packetType The type of the packet being sent.
     * @param adapterParams Additional parameters required for the adapter.
     * @param extraGas Extra gas to be added to the minimum required gas.
     */
    function _checkGasLimit(uint16 dstChainId, uint16 packetType, bytes memory adapterParams, uint256 extraGas)
        internal
        view
        virtual
    {
        LzAppStorage storage $ = _getLzAppStorage();
        uint256 providedGasLimit = _getGasLimit(adapterParams);
        uint256 minGasLimit = $.minDstGasLookup[dstChainId][packetType];
        require(minGasLimit != 0, "LzApp: minGasLimit not set");
        require(providedGasLimit >= minGasLimit + extraGas, "LzApp: gas limit is too low");
    }

    /**
     * @dev Internal function to extract the gas limit from the adapter parameters.
     *
     * Requirements:
     * - The `adapterParams` must be at least 34 bytes long to contain the gas limit.
     *
     * @param _adapterParams The adapter parameters from which the gas limit is to be extracted.
     * @return gasLimit The extracted gas limit.
     */
    function _getGasLimit(bytes memory _adapterParams) internal pure virtual returns (uint256 gasLimit) {
        require(_adapterParams.length >= 34, "LzApp: invalid adapterParams");
        // slither-disable-next-line assembly
        assembly {
            gasLimit := mload(add(_adapterParams, 34))
        }
    }

    /**
     * @dev Internal function to validate the size of the payload against the configured limit for a given destination
     * chain.
     *
     * Requirements:
     * - Payload size must be less than or equal to the configured size limit for the given destination chain.
     *
     * @param _dstChainId The ID of the destination chain.
     * @param _payloadSize The size of the payload in bytes.
     */
    function _checkPayloadSize(uint16 _dstChainId, uint256 _payloadSize) internal view virtual {
        LzAppStorage storage $ = _getLzAppStorage();
        uint256 payloadSizeLimit = $.payloadSizeLimitLookup[_dstChainId];
        if (payloadSizeLimit == 0) {
            // use default if not set
            payloadSizeLimit = DEFAULT_PAYLOAD_SIZE_LIMIT;
        }
        require(_payloadSize <= payloadSizeLimit, "LzApp: payload size is too large");
    }

    /**
     * @dev Retrieves the configuration of the LayerZero user application for a given version, chain ID, and config
     * type.
     *
     * @param version The version for which the configuration is to be fetched.
     * @param chainId The ID of the chain for which the configuration is needed.
     * @param configType The type of the configuration to be retrieved.
     * @return The bytes representation of the configuration.
     */
    function getConfig(uint16 version, uint16 chainId, address, uint256 configType)
        external
        view
        returns (bytes memory)
    {
        return lzEndpoint.getConfig(version, chainId, address(this), configType);
    }

    /**
     * @dev Sets the configuration of the LayerZero user application for a given version, chain ID, and config type.
     *
     * Requirements:
     * - Only the owner can set the configuration.
     *
     * @param version The version for which the configuration is to be set.
     * @param chainId The ID of the chain for which the configuration is being set.
     * @param configType The type of the configuration to be set.
     * @param config The actual configuration data in bytes format.
     */
    function setConfig(uint16 version, uint16 chainId, uint256 configType, bytes calldata config)
        external
        override
        onlyOwner
    {
        lzEndpoint.setConfig(version, chainId, configType, config);
    }

    /**
     * @dev Sets the version to be used for sending LayerZero messages.
     *
     * Requirements:
     * - Only the owner can set the send version.
     *
     * @param version The version to be set for sending messages.
     */
    function setSendVersion(uint16 version) external override onlyOwner {
        lzEndpoint.setSendVersion(version);
    }

    /**
     * @dev Sets the version to be used for receiving LayerZero messages.
     *
     * Requirements:
     * - Only the owner can set the receive version.
     *
     * @param version The version to be set for receiving messages.
     */
    function setReceiveVersion(uint16 version) external override onlyOwner {
        lzEndpoint.setReceiveVersion(version);
    }

    /**
     * @dev Resumes the reception of LayerZero messages from a specific source chain and address.
     *
     * Requirements:
     * - Only the owner can force the resumption of message reception.
     *
     * @param srcChainId The ID of the source chain from which message reception is to be resumed.
     * @param srcAddress The address on the source chain for which message reception is to be resumed.
     */
    function forceResumeReceive(uint16 srcChainId, bytes calldata srcAddress) external override onlyOwner {
        lzEndpoint.forceResumeReceive(srcChainId, srcAddress);
    }

    /**
     * @dev Sets the trusted path for cross-chain communication with a specified remote chain.
     *
     * Requirements:
     * - Only the owner can set the trusted path.
     *
     * @param remoteChainId The ID of the remote chain for which the trusted path is being set.
     * @param path The trusted path encoded as bytes.
     */
    function setTrustedRemote(uint16 remoteChainId, bytes calldata path) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.trustedRemoteLookup[remoteChainId] = path;
        emit SetTrustedRemote(remoteChainId, path);
    }

    /**
     * @dev Sets the trusted remote address for cross-chain communication with a specified remote chain.
     * The function also automatically appends the contract's own address to the path.
     *
     * Requirements:
     * - Only the owner can set the trusted remote address.
     *
     * @param remoteChainId The ID of the remote chain for which the trusted address is being set.
     * @param remoteAddress The trusted remote address encoded as bytes.
     */
    function setTrustedRemoteAddress(uint16 remoteChainId, bytes calldata remoteAddress) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.trustedRemoteLookup[remoteChainId] = abi.encodePacked(remoteAddress, address(this));
        emit SetTrustedRemoteAddress(remoteChainId, remoteAddress);
    }

    /**
     * @dev Retrieves the trusted remote address for a given remote chain.
     *
     * Requirements:
     * - A trusted path record must exist for the specified remote chain.
     *
     * @param remoteChainId The ID of the remote chain for which the trusted address is needed.
     * @return The trusted remote address encoded as bytes.
     */
    function getTrustedRemoteAddress(uint16 remoteChainId) external view returns (bytes memory) {
        LzAppStorage storage $ = _getLzAppStorage();
        bytes memory path = $.trustedRemoteLookup[remoteChainId];
        require(path.length != 0, "LzApp: no trusted path record");
        return path.slice(0, path.length - 20); // the last 20 bytes should be address(this)
    }

    /**
     * @dev Sets the "Precrime" address, which could be an address for handling fraudulent activities or other specific
     * behaviors.
     *
     * Requirements:
     * - Only the owner can set the Precrime address.
     *
     * @param _precrime The address to be set as Precrime.
     */
    function setPrecrime(address _precrime) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.precrime = _precrime;
        emit SetPrecrime(_precrime);
    }

    /**
     * @dev Sets the minimum required gas for a specific packet type and destination chain.
     *
     * Requirements:
     * - Only the owner can set the minimum destination gas.
     *
     * @param dstChainId The ID of the destination chain for which the minimum gas is being set.
     * @param packetType The type of the packet for which the minimum gas is being set.
     * @param minGas The minimum required gas in units.
     */
    function setMinDstGas(uint16 dstChainId, uint16 packetType, uint256 minGas) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.minDstGasLookup[dstChainId][packetType] = minGas;
        emit SetMinDstGas(dstChainId, packetType, minGas);
    }

    /**
     * @dev Sets the payload size limit for a specific destination chain.
     *
     * Requirements:
     * - Only the owner can set the payload size limit.
     *
     * @param dstChainId The ID of the destination chain for which the payload size limit is being set.
     * @param size The size limit in bytes.
     */
    function setPayloadSizeLimit(uint16 dstChainId, uint256 size) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.payloadSizeLimitLookup[dstChainId] = size;
    }

    /**
     * @dev Checks whether a given source chain and address are trusted for receiving LayerZero messages.
     *
     * @param srcChainId The ID of the source chain to be checked.
     * @param srcAddress The address on the source chain to be verified.
     * @return A boolean indicating whether the source chain and address are trusted.
     */
    function isTrustedRemote(uint16 srcChainId, bytes calldata srcAddress) external view returns (bool) {
        LzAppStorage storage $ = _getLzAppStorage();
        bytes memory trustedSource = $.trustedRemoteLookup[srcChainId];
        return keccak256(trustedSource) == keccak256(srcAddress);
    }
}

// lib/tangible-foundation-contracts/src/layerzero/lzApp/NonblockingLzAppUpgradeable.sol

/**
 * @title Nonblocking LayerZero Application
 * @dev This contract extends LzAppUpgradeable and modifies its behavior to be non-blocking. Failed messages are caught
 * and stored for future retries, ensuring that the message channel remains unblocked. This contract serves as an
 * abstract base class and should be extended by specific implementations.
 *
 * Note: If the `srcAddress` is not configured properly, it will still block the message pathway from (`srcChainId`,
 * `srcAddress`).
 */
abstract contract NonblockingLzAppUpgradeable is LzAppUpgradeable {
    using ExcessivelySafeCall for address;

    event MessageFailed(uint16 srcChainId, bytes srcAddress, uint64 nonce, bytes payload, bytes reason);
    event RetryMessageSuccess(uint16 srcChainId, bytes srcAddress, uint64 nonce, bytes32 payloadHash);

    /// @custom:storage-location erc7201:layerzero.storage.NonblockingLzApp
    struct NonblockingLzAppStorage {
        mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) failedMessages;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.NonblockingLzApp")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NonblockingLzAppStorageLocation =
        0xe5a86fa43fa85f564c84895bd4f80ec5c29d03a57a0c1f7cb91d2cc05b4d8600;

    function _getNonblockingLzAppStorage() private pure returns (NonblockingLzAppStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := NonblockingLzAppStorageLocation
        }
    }

    /**
     * @param endpoint The address of the LayerZero endpoint contract.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) LzAppUpgradeable(endpoint) {}

    /**
     * @dev Initializes the contract, setting the initial owner and endpoint addresses.
     * Also chains the initialization process with the base `LzAppUpgradeable` contract.
     *
     * Requirements:
     * - Can only be called during contract initialization.
     *
     * @param initialOwner The address that will initially own the contract.
     */
    function __NonblockingLzApp_init(address initialOwner) internal onlyInitializing {
        __NonblockingLzApp_init_unchained();
        __LzApp_init(initialOwner);
    }

    function __NonblockingLzApp_init_unchained() internal onlyInitializing {}

    /**
     * @dev Retrieves the hash of the payload of a failed message for a given source chain, source address, and nonce.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the failed message.
     * @return payloadHash The hash of the payload of the failed message.
     */
    function failedMessages(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce)
        external
        view
        returns (bytes32 payloadHash)
    {
        NonblockingLzAppStorage storage $ = _getNonblockingLzAppStorage();
        return $.failedMessages[srcChainId][srcAddress][nonce];
    }

    /**
     * @dev Internal function that receives LayerZero messages and attempts to process them in a non-blocking manner.
     * If processing fails, the message is stored for future retries.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the message.
     * @param payload The payload of the message.
     */
    function _blockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual
        override
    {
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(this.nonblockingLzReceive.selector, srcChainId, srcAddress, nonce, payload)
        );
        // try-catch all errors/exceptions
        if (!success) {
            _storeFailedMessage(srcChainId, srcAddress, nonce, payload, reason);
        }
    }

    /**
     * @dev Internal function to store the details of a failed message for future retries.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the failed message.
     * @param payload The payload of the failed message.
     * @param reason The reason for the message's failure.
     */
    function _storeFailedMessage(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload,
        bytes memory reason
    ) internal virtual {
        NonblockingLzAppStorage storage $ = _getNonblockingLzAppStorage();
        $.failedMessages[srcChainId][srcAddress][nonce] = keccak256(payload);
        emit MessageFailed(srcChainId, srcAddress, nonce, payload, reason);
    }

    /**
     * @dev Public wrapper function for handling incoming LayerZero messages in a non-blocking manner.
     * It internally calls the `_nonblockingLzReceive` function, which should be overridden in derived contracts.
     *
     * Requirements:
     * - The caller must be the contract itself.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the message.
     * @param payload The payload of the message.
     */
    function nonblockingLzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        public
        virtual
    {
        // only internal transaction
        require(_msgSender() == address(this), "NonblockingLzApp: caller must be LzApp");
        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    /**
     * @dev Internal function that should be overridden in derived contracts to implement the logic
     * for processing incoming LayerZero messages in a non-blocking manner.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the message.
     * @param payload The payload of the message.
     */
    function _nonblockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual;

    /**
     * @dev Allows for the manual retry of a previously failed message.
     *
     * Requirements:
     * - There must be a stored failed message matching the provided parameters.
     * - The payload hash must match the stored failed message.
     *
     * @param srcChainId The ID of the source chain where the failed message originated.
     * @param srcAddress The address on the source chain where the failed message originated.
     * @param nonce The nonce of the failed message.
     * @param payload The payload of the failed message.
     */
    function retryMessage(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        public
        payable
        virtual
    {
        NonblockingLzAppStorage storage $ = _getNonblockingLzAppStorage();
        mapping(uint64 => bytes32) storage _failedMessages = $.failedMessages[srcChainId][srcAddress];

        // get the payload hash value
        bytes32 payloadHash = _failedMessages[nonce];

        // assert there is message to retry
        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
        require(keccak256(payload) == payloadHash, "NonblockingLzApp: invalid payload");

        // clear the stored message
        _failedMessages[nonce] = bytes32(0);

        // execute the message. revert if it fails again
        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
        emit RetryMessageSuccess(srcChainId, srcAddress, nonce, payloadHash);
    }
}

// lib/tangible-foundation-contracts/src/layerzero/token/oft/v1/OFTCoreUpgradeable.sol

/**
 * @title OFTCoreUpgradeable
 * @dev This contract extends NonblockingLzAppUpgradeable to provide a core implementation for OFT (On-Chain Forwarding
 * Token). It introduces packet types, custom adapter params, and methods for sending and receiving tokens across
 * chains.
 *
 * This contract is intended to be inherited by other contracts that implement specific token logic.
 *
 * Packet Types:
 * - PT_SEND: Packet type for sending tokens. Value is 0.
 *
 * Custom Adapter Params:
 * - The contract allows for the use of custom adapter parameters which affect the gas usage for cross-chain operations.
 *
 * Storage:
 * - useCustomAdapterParams: A flag to indicate whether to use custom adapter parameters.
 */
abstract contract OFTCoreUpgradeable is NonblockingLzAppUpgradeable, ERC165, IOFTCore {
    using BytesLib for bytes;

    uint256 public constant NO_EXTRA_GAS = 0;

    // packet type
    uint16 public constant PT_SEND = 0;

    /// @custom:storage-location erc7201:layerzero.storage.OFTCore
    struct OFTCoreStorage {
        bool useCustomAdapterParams;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.OFTCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OFTCoreStorageLocation = 0x822492242235517548c4a8cf040400e3c0daf5b82af652ed16dce4fa3ae72800;

    function _getOFTCoreStorage() private pure returns (OFTCoreStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OFTCoreStorageLocation
        }
    }

    /**
     * @param endpoint The address of the LayerZero endpoint.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) NonblockingLzAppUpgradeable(endpoint) {}

    /**
     * @dev Initializes the contract state for `OFTCoreUpgradeable`.
     * Calls the initialization functions of parent contracts.
     *
     * @param initialOwner The address of the initial owner.
     */
    function __OFTCore_init(address initialOwner) internal onlyInitializing {
        __OFTCore_init_unchained();
        __NonblockingLzApp_init(initialOwner);
    }

    function __OFTCore_init_unchained() internal onlyInitializing {}

    /**
     * @dev Checks if the contract supports a given interface ID.
     * Overrides the implementation in ERC165 to include support for IOFTCore.
     *
     * @param interfaceId The ID of the interface to check.
     * @return bool `true` if the contract supports the given interface ID, `false` otherwise.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOFTCore).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Estimates the fee required for sending tokens to a different chain.
     * This function is part of the IOFTCore interface.
     *
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The address to which the tokens will be sent on the destination chain.
     * @param amount The amount of tokens to send.
     * @param useZro Flag indicating whether to use ZRO for payment.
     * @param adapterParams Additional parameters for the adapter.
     * @return nativeFee The estimated native chain fee.
     * @return zroFee The estimated ZRO fee.
     */
    function estimateSendFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        bool useZro,
        bytes calldata adapterParams
    ) public view virtual override returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for sendFrom()
        bytes memory payload = abi.encode(PT_SEND, toAddress, amount);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, useZro, adapterParams);
    }

    /**
     * @dev Sends tokens from a given address to a destination address on another chain.
     * This function is part of the IOFTCore interface.
     *
     * @param from The address from which tokens will be sent.
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The address on the destination chain to which tokens will be sent.
     * @param amount The amount of tokens to send.
     * @param refundAddress The address where any excess native fee will be refunded.
     * @param zroPaymentAddress The address used for ZRO payments, if applicable.
     * @param adapterParams Additional parameters for the adapter.
     */
    function sendFrom(
        address from,
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) public payable virtual override {
        _send(from, dstChainId, toAddress, amount, refundAddress, zroPaymentAddress, adapterParams);
    }

    /**
     * @dev Toggles the use of custom adapter parameters.
     * When enabled, the contract will check gas limits based on the provided adapter parameters.
     *
     * @param useCustomAdapterParams Flag indicating whether to use custom adapter parameters.
     */
    function setUseCustomAdapterParams(bool useCustomAdapterParams) public virtual onlyOwner {
        OFTCoreStorage storage $ = _getOFTCoreStorage();
        $.useCustomAdapterParams = useCustomAdapterParams;
        emit SetUseCustomAdapterParams(useCustomAdapterParams);
    }

    /**
     * @dev Handles incoming messages from other chains in a non-blocking fashion.
     * This function overrides the abstract implementation in NonblockingLzAppUpgradeable.
     *
     * @param srcChainId The ID of the source chain.
     * @param srcAddress The address on the source chain from which the message originated.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data sent from the source chain.
     */
    function _nonblockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual
        override
    {
        uint16 packetType;

        // slither-disable-next-line assembly
        assembly {
            packetType := mload(add(payload, 32))
        }

        if (packetType == PT_SEND) {
            _sendAck(srcChainId, srcAddress, nonce, payload);
        } else {
            revert("OFTCore: unknown packet type");
        }
    }

    /**
     * @dev Performs the actual sending of tokens to a destination chain.
     * This internal function is called by the public wrapper `sendFrom`.
     *
     * @param from The address from which tokens are sent.
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The address on the destination chain where tokens will be sent.
     * @param amount The amount of tokens to send.
     * @param refundAddress The address for refunding any excess native fee.
     * @param zroPaymentAddress The address for ZRO payment, if applicable.
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
    ) internal virtual {
        _checkAdapterParams(dstChainId, PT_SEND, adapterParams, NO_EXTRA_GAS);

        amount = _debitFrom(from, dstChainId, toAddress, amount);

        bytes memory lzPayload = abi.encode(PT_SEND, toAddress, amount);
        _lzSend(dstChainId, lzPayload, refundAddress, zroPaymentAddress, adapterParams, msg.value);

        emit SendToChain(dstChainId, from, toAddress, amount);
    }

    /**
     * @dev Acknowledges the reception of tokens sent from another chain.
     * This function is called internally when a PT_SEND packet type is received.
     *
     * @param srcChainId The ID of the source chain from which the tokens were sent.
     * @param srcAddressBytes The address on the source chain from which the message originated.
     * @param payload The payload containing the details of the sent tokens.
     */
    function _sendAck(uint16 srcChainId, bytes memory srcAddressBytes, uint64, bytes memory payload) internal virtual {
        (, bytes memory toAddressBytes, uint256 amount) = abi.decode(payload, (uint16, bytes, uint256));

        address src = srcAddressBytes.toAddress(0);
        address to = toAddressBytes.toAddress(0);

        amount = _creditTo(srcChainId, to, amount);

        // send the acknowledgement to the receiver for the amount credited from the source chain
        try IOFTSubscriber(to).notifyCredit(srcChainId, address(this), src, amount) {} catch {}

        emit ReceiveFromChain(srcChainId, to, amount);
    }

    /**
     * @dev Validates the adapter parameters for sending tokens.
     * This function can be configured to either enforce a gas limit or to accept custom parameters.
     *
     * @param dstChainId The ID of the destination chain.
     * @param pkType The packet type of the message.
     * @param adapterParams The additional parameters for the adapter.
     * @param extraGas The extra gas that may be needed for execution.
     */
    function _checkAdapterParams(uint16 dstChainId, uint16 pkType, bytes memory adapterParams, uint256 extraGas)
        internal
        virtual
    {
        OFTCoreStorage storage $ = _getOFTCoreStorage();
        if ($.useCustomAdapterParams) {
            _checkGasLimit(dstChainId, pkType, adapterParams, extraGas);
        } else {
            require(adapterParams.length == 0, "OFTCore: _adapterParams must be empty.");
        }
    }

    /**
     * @dev Debits an amount of tokens from the specified address.
     * This is an internal function that should be overridden to handle the actual token transfer logic.
     *
     * @param from The address from which tokens will be debited.
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The encoded destination address on the target chain.
     * @param amount The amount of tokens to debit.
     * @return The final amount of tokens that were debited. This allows for potential adjustments.
     */
    function _debitFrom(address from, uint16 dstChainId, bytes memory toAddress, uint256 amount)
        internal
        virtual
        returns (uint256);

    /**
     * @dev Credits an amount of tokens to a specific address.
     * This is an internal function that should be overridden to handle the actual token crediting logic.
     *
     * @param srcChainId The ID of the source chain from which the tokens were sent.
     * @param toAddress The address to which tokens will be credited.
     * @param amount The amount of tokens to credit.
     * @return The final amount of tokens that were credited. This allows for potential adjustments.
     */
    function _creditTo(uint16 srcChainId, address toAddress, uint256 amount) internal virtual returns (uint256);
}

// lib/tangible-foundation-contracts/src/layerzero/token/oft/v1/OFTUpgradeable.sol

/**
 * @title OFTUpgradeable
 * @dev This contract is an upgradable implementation of LayerZero's Omnichain Fungible Tokens (OFT) standard.
 * It inherits the core functionalities from OFTCoreUpgradeable and extends it by adding ERC-20 token functionalities.
 * This contract is designed to allow the token to be transacted across different blockchains in a seamless manner.
 *
 * Key methods include `_debitFrom` and `_creditTo`, which are overridden to handle the actual token transactions.
 * This contract is also compatible with the ERC-165 standard for contract introspection.
 */
contract OFTUpgradeable is OFTCoreUpgradeable, ERC20Upgradeable, IOFT {
    /**
     * @param endpoint The address of the LayerZero endpoint.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) OFTCoreUpgradeable(endpoint) {}

    /**
     * @dev Initializes the OFT token with a given name and symbol.
     * It sets the state within this contract and also initializes the inherited ERC20 token with the given name and
     * symbol.
     * This function should only be called during the contract initialization phase.
     *
     * @param initialOwner The address of the initial owner.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function __OFT_init(address initialOwner, string memory name, string memory symbol) internal onlyInitializing {
        __OFT_init_unchained();
        __OFTCore_init(initialOwner);
        __ERC20_init(name, symbol);
    }

    function __OFT_init_unchained() internal onlyInitializing {}

    /**
     * @dev Implements the ERC165 standard for contract introspection.
     * Extends the functionality to include the interface IDs of IOFT and IERC20, alongside the inherited interfaces.
     *
     * @param interfaceId The interface identifier, as specified in ERC-165.
     * @return `true` if the contract implements the interface represented by `interfaceId`, otherwise `false`.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(OFTCoreUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IOFT).interfaceId || interfaceId == type(IERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Retrieves the address of the OFT token, which is the address of this contract.
     * This function is part of the IOFT interface.
     *
     * @return The address of this OFT token contract.
     */
    function token() public view virtual override returns (address) {
        return address(this);
    }

    /**
     * @dev Returns the total circulating supply of OFT tokens.
     * In this implementation, it's equivalent to the total supply as managed by the ERC20 standard.
     * This function is part of the IOFT interface.
     *
     * @return The total circulating supply of OFT tokens.
     */
    function circulatingSupply() public view virtual override returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Handles the token debit operation when sending tokens to another chain.
     * Burns the specified amount of tokens from the sender's account.
     *
     * @param from The address of the token holder.
     * @param amount The amount of tokens to be debited (burned).
     * @return The actual amount of tokens that were debited.
     */
    function _debitFrom(address from, uint16, bytes memory, uint256 amount)
        internal
        virtual
        override
        returns (uint256)
    {
        address spender = _msgSender();
        if (from != spender) _spendAllowance(from, spender, amount);
        _burn(from, amount);
        return amount;
    }

    /**
     * @dev Handles the token credit operation when receiving tokens from another chain.
     * Mints the specified amount of tokens to the recipient's account.
     *
     * @param toAddress The address of the recipient.
     * @param amount The amount of tokens to be credited (minted).
     * @return The actual amount of tokens that were credited.
     */
    function _creditTo(uint16, address toAddress, uint256 amount) internal virtual override returns (uint256) {
        _mint(toAddress, amount);
        return amount;
    }
}

// src/staking/WrappedstRWASatellite.sol

/**
 * @title WrappedstRWASatellite
 * @notice Staked RWA Satellite Token allowing for cross-chain bridging of the 'stRWA' token.
 */
contract WrappedstRWASatellite is UUPSUpgradeable, OFTUpgradeable {
    // ~ Constructor ~

    /**
     * @notice Initializes WrappedstRWASatellite.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     */
    constructor(address lzEndpoint) OFTUpgradeable(lzEndpoint) {
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
}
