// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// tangible imports
import { NonblockingLzAppUpgradeable } from "@tangible-foundation-contracts/layerzero/lzApp/NonblockingLzAppUpgradeable.sol";

// passive income nft imports
import { PassiveIncomeNFT } from "./refs/PassiveIncomeNFT.sol";
import { PassiveIncomeCalculator } from "./refs/PassiveIncomeCalculator.sol";

// local
import { VotingMath } from "./governance/VotingMath.sol";

/**
 * @title CrossChainMigrator
 * @author @chasebrownn
 * @notice This contract handles migration of $TNGBL holders and 3,3+ NFT holders. This contract will facilitate a migration
 *         from Polygon to Tangible's new Real Chain. The migrators will receive the RWA or veRWA equivalent on Real Chain.
 *         This contract takes advantage of the LayerZero protocol to facilitate cross-chain messaging.
 *
 * Key Features:
 * - On 3,3+ NFT migrations, the CrossChainMigrator contract will take the 3,3+ NFT into custody and send a 
 *   message containing all of the current lock data to the RealReceiver on Real Chain.
 * - Does support batch NFT migrations for any users who hold more than one 3,3+ NFT.
 * - On $TNGBL migrations, the CrossChainMigrator contract will burn the migrated $TNGBL tokens and send a 
 *   message to the RealReceiver on Real Chain to mint new tokens.
 */
contract CrossChainMigrator is OwnableUpgradeable, NonblockingLzAppUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using VotingMath for uint256;

    // ---------------
    // State Variables
    // ---------------

    /// @notice max vesting duration.
    uint256 private constant MAX_VESTING_DURATION = VotingMath.MAX_VESTING_DURATION;
    /// @notice Packet type for ERC-20 token migration message.
    uint16 private constant SEND = 0;
    /// @notice Packet type for NFT migration message.
    uint16 private constant SEND_NFT = 1;
    /// @notice Packet type for NFT batch migration message.
    uint16 private constant SEND_NFT_BATCH = 2;
    /// @notice Stores address of remote chain message Receiver contract for NFTs -> Where we're going.
    /// @dev The LZ Relayer will be transmitting the NFT migration messages to this contract.
    address public receiver;
    /// @notice Contract reference for passiveIncomeNFT.
    PassiveIncomeNFT public passiveIncomeNFT;
    /// @notice Contract address for TNGBL ERC-20 token.
    ERC20Burnable public tngblToken;
    /// @notice Remote chainId. ChainId for Real Chain.
    uint16 public remoteChainId;
    /// @notice If true, migration can commence.
    bool public migrationActive;
    /// @notice If true, migration message payloads will require a custom `adapterParams` argument.
    bool public useCustomAdapterParams;
    /// @notice Contact reference for passive income calculator.
    PassiveIncomeCalculator public piCalculator;

    struct LockCache {
        uint256 startTime;
        uint256 endTime;
        uint256 lockedAmount;
        uint256 multiplier;
        uint256 claimed;
        uint256 maxPayout;
    }

    /// @notice boost start time for passiveIncomeNFT locks.
    uint256 private BOOST_START;
    /// @notice boost end time for passiveIncomeNFT locks.
    uint256 private BOOST_END;


    // ------
    // Errors
    // ------

    /**
     * @notice This error is emitted when a migration message fails to be sent to the LZ endpoint.
     */
    error FailedMigration();

    /**
     * @notice This error is emitted when a user attempts to mirgate an expired NFT.
     */
    error ExpiredNFT(uint256 tokenId);


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when there's a successful execution of `migrateNFT`.
     * @param account Address of migrator.
     * @param tokenId Token identifier that was migrated.
     * @param amount Amount of RWA that will be minted on destination chain for this new veRWA token.
     * @param vp Voting power that will be granted with the new veRWA token.
     */
    event MigrationMessageSent_PINFT(address indexed account, uint256 indexed tokenId, uint256 amount, uint256 vp);

    /**
     * @notice This event is emitted when there's a successful execution of `migrateTokens`.'
     * @param account Adress of migrator.
     * @param amount Amount of ERC-20 tokens migrated.
     */
    event MigrationInFlight_TNGBL(address indexed account, uint256 amount);

    /**
     * @notice This event is emitted when migration is toggled on/off.
     * @param newState If true, migration is enabled, otherwise false.
     */
    event MigrationToggled(bool indexed newState);

    
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
     * @notice This method initializes the CrossChainMigrator contract.
     * @param _legacyPINFT Contract address of PassiveIncomeNFT.
     * @param _piCalc Contract address of PassiveIncomeCalculator.
     * @param _legacyTngbl Contract address of TNGBL token.
     * @param _receiver RealReceiver contract address on destination chain.
     * @param _remoteChainId Chain Id of destination chain.
     * @param _admin Default admin address.
     */
    function initialize(
        address _legacyPINFT,
        address _piCalc,
        address _legacyTngbl,
        address _receiver,
        uint16 _remoteChainId,
        address _admin
    ) external initializer {
        require(_admin != address(0));
        require(_remoteChainId != uint16(0));

        __Ownable_init(_admin);
        __NonblockingLzApp_init(_admin);
        __UUPSUpgradeable_init();
        
        useCustomAdapterParams = true;

        passiveIncomeNFT = PassiveIncomeNFT(_legacyPINFT);
        piCalculator = PassiveIncomeCalculator(_piCalc);
        tngblToken = ERC20Burnable(_legacyTngbl);

        receiver = _receiver;

        // destination chain id
        remoteChainId = _remoteChainId;

        BOOST_START = passiveIncomeNFT.boostStartTime();
        BOOST_END = passiveIncomeNFT.boostEndTime();
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method is used to migrate a single PassiveIncome NFT from Polygon to Real chain.
     * @dev This method will take a user's PI NFT specified and send a message to the Polygon LayerZero endpoint to be
     *      later passed to the destination chain.
     *      msg.value must not be 0. Specify an amount to pay for gas. You can get a gas quote from endpoint::estimateFees().
     * @param _tokenId Token identifier of PI NFT that is being migrated to the new chain.
     * @param to Receiver on destination chain of migrated NFT.
     * @param refundAddress Address of EOA to receive a refund if fees needed is less than what was quoted.
     * @param adapterParams Extra parameter that is passed in the event the migrator wants to receive an airdrop of native ETH
     *        on the destination chain. For more info on how to use this param:
     *        https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters
     */
    function migrateNFT(
        uint256 _tokenId,
        address to,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) payable external {
        require(migrationActive, "CrossChainMigrator: Migration is not active");

        // Transfer NFT into this contract. Keep custody
        passiveIncomeNFT.transferFrom(msg.sender, address(this), _tokenId);

        _checkAdapterParams(remoteChainId, SEND_NFT, adapterParams, 0);

        (uint256 startTime,
        uint256 endTime,
        uint256 lockedAmount,
        uint256 multiplier,
        uint256 claimed,
        uint256 maxPayout) = passiveIncomeNFT.locks(_tokenId);

        uint256 amountTokens;
        if (multiplier != piCalculator.determineMultiplier(BOOST_START, BOOST_END, startTime, uint8((endTime - startTime) / 30 days))) {
            // if early claim, just mint them remaining in `maxPayout`.
            amountTokens = maxPayout;
        }
        else {
            // otherwise, just calculate amount to mint/lock as normal.
            amountTokens = lockedAmount + ((lockedAmount * (multiplier - 1e18)) / 1e18) - claimed;
        }

        // if lock is expired -> revert
        if (block.timestamp >= endTime) {
            revert ExpiredNFT(_tokenId);
        }

        uint256 duration = endTime - block.timestamp;

        if (duration > MAX_VESTING_DURATION) {
            duration = MAX_VESTING_DURATION;
        }
        
        _lzSend(
            remoteChainId,
            abi.encode(SEND_NFT, abi.encodePacked(to), amountTokens, duration),
            refundAddress,
            zroPaymentAddress,
            adapterParams,
            msg.value
        );

        emit MigrationMessageSent_PINFT(
            msg.sender,
            _tokenId,
            amountTokens,
            SafeCast.toUint208(amountTokens.calculateVotingPower(duration))
        );
    }

    /**
     * @notice This method is used to migrate a batch of PassiveIncome NFTs from Polygon to Real chain.
     * @dev This method will take a user's PI NFTs specified and send a message to the Polygon LayerZero endpoint to be
     *      later passed to the destination chain for a batch migration.
     *      msg.value must not be 0. Specify an amount to pay for gas. You can get a gas quote from endpoint::estimateFees().
     * @param _tokenIds Token identifiers of PI NFTs that are being migrated to the new chain.
     * @param to Receiver on destination chain of migrated NFT.
     * @param refundAddress Address of EOA to receive a refund if fees needed is less than what was quoted.
     * @param adapterParams Extra parameter that is passed in the event the migrator wants to receive an airdrop of native ETH
     *        on the destination chain. For more info on how to use this param:
     *        https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters
     */
    function migrateNFTBatch(
        uint256[] memory _tokenIds,
        address to,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) payable external nonReentrant {
        require(migrationActive, "CrossChainMigrator: Migration is not active");

        uint256[] memory lockedAmounts = new uint256[](_tokenIds.length);
        uint256[] memory durations = new uint256[](_tokenIds.length);

        for (uint256 i; i < _tokenIds.length;) {
            // Transfer NFT into this contract. Keep custody
            passiveIncomeNFT.transferFrom(msg.sender, address(this), _tokenIds[i]);

            LockCache memory lCache;

            (lCache.startTime,
            lCache.endTime,
            lCache.lockedAmount,
            lCache.multiplier,
            lCache.claimed,
            lCache.maxPayout) = passiveIncomeNFT.locks(_tokenIds[i]);

            uint8 durationInMonths = uint8((lCache.endTime - lCache.startTime) / 30 days);

            if (lCache.multiplier != piCalculator.determineMultiplier(BOOST_START, BOOST_END, lCache.startTime, durationInMonths)) {
                // if early claim, just mint them remaining in `maxPayout`.
                lockedAmounts[i] = lCache.maxPayout;
            }
            else {
                // otherwise, just calculate amount to mint/lock as normal.
                lockedAmounts[i] = lCache.lockedAmount + ((lCache.lockedAmount * (lCache.multiplier - 1e18)) / 1e18) - lCache.claimed;
            }

            // if lock is expired -> revert
            if (block.timestamp >= lCache.endTime) {
                revert ExpiredNFT(_tokenIds[i]);
            }

            durations[i] = lCache.endTime - block.timestamp;

            if (durations[i] > MAX_VESTING_DURATION) {
                durations[i] = MAX_VESTING_DURATION;
            }

            emit MigrationMessageSent_PINFT(
                msg.sender,
                _tokenIds[i],
                lockedAmounts[i],
                SafeCast.toUint208(lockedAmounts[i].calculateVotingPower(durations[i]))
            );

            unchecked {
                ++i;
            }
        }

        _checkAdapterParams(remoteChainId, SEND_NFT_BATCH, adapterParams, 0);

        _lzSend(
            remoteChainId,
            abi.encode(SEND_NFT_BATCH, abi.encodePacked(to), lockedAmounts, durations),
            refundAddress,
            zroPaymentAddress,
            adapterParams,
            msg.value
        );
    }

    /**
     * @notice This method is used to migrate TNGBL tokens from Polygon to RWA on Real chain.
     * @dev This method will burn TNGBL tokens from the migrator then send a mintFor message to the RWA
     *      contract on Real chain.
     *      msg.value must not be 0. Specify an amount to pay for gas. You can get a gas quote from endpoint::estimateFees().
     * @param _amount Amount of TNGBL tokens that are being migrated/burned. The amount of RWA minted will be 1-to-1.
     * @param to Receiver on destination chain of migrated ERC-20 tokens.
     * @param refundAddress Address of EOA to receive a refund if fees needed is less than what was quoted.
     * @param adapterParams Extra parameter that is passed in the event the migrator wants to receive an airdrop of native ETH
     *        on the destination chain. For more info on how to use this param:
     *        https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters
     */
    function migrateTokens(
        uint256 _amount,
        address to,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external payable {
        require(migrationActive, "CrossChainMigrator: Migration is not active");
        require(tngblToken.balanceOf(msg.sender) >= _amount, "CrossChainMigrator: Insufficient balance");

        tngblToken.transferFrom(msg.sender, address(this), _amount);

        _checkAdapterParams(remoteChainId, SEND, adapterParams, 0);

        bytes memory lzPayload = abi.encode(SEND, abi.encodePacked(to), _amount);

        _lzSend(remoteChainId, lzPayload, refundAddress, zroPaymentAddress, adapterParams, msg.value);

        emit MigrationInFlight_TNGBL(msg.sender, _amount);
    }

    function burnToken(uint256 tokenId) external onlyOwner {
        require(passiveIncomeNFT.ownerOf(tokenId) == address(this), "CrossChainMigrator: not owner");

        (,uint256 endTime,
        uint256 lockedAmount,
        uint256 multiplier,
        uint256 claimed,) = passiveIncomeNFT.locks(tokenId);

        uint256 totalRewardAmount = (lockedAmount * (multiplier - 1e18)) / 1e18;

        require(block.timestamp >= endTime, "CrossChainMigrator: not expired");

        uint256 amount = lockedAmount + totalRewardAmount;

        if (amount > claimed) {
            unchecked {
                amount = amount - claimed;
            }
        } else {
            amount = 0;
        }

        uint256 received = passiveIncomeNFT.burn(tokenId);
        uint256 excessAmount = received - amount;

        if (excessAmount != 0) {
            tngblToken.transfer(address(passiveIncomeNFT), excessAmount);
        }

        _burnTngbl();
    }

    /**
     * @notice This method allows a permissioned admin address to toggle migratino on/off.
     */
    function toggleMigration() external onlyOwner {
        migrationActive = !migrationActive;
        emit MigrationToggled(migrationActive);
    }

    /**
     * @notice This method allows a permissioned admin to update the `tngblToken` address.
     * @dev This is mainly for testnet since the current mainnet TNGBL contract will not change.
     */
    function setTngblAddress(address _newContract) external onlyOwner {
        require(_newContract != address(0), "invalid input");
        tngblToken = ERC20Burnable(_newContract);
    }

    /**
     * @notice This method allows a permissioned admin to update the `passiveIncomeNFT` address.
     * @dev This is mainly for testnet since the current mainnet PI NFT contract will not change.
     */
    function setPassiveIncomeNFTAddress(address _newContract) external onlyOwner {
        require(_newContract != address(0), "invalid input");
        passiveIncomeNFT = PassiveIncomeNFT(_newContract);
    }

    /**
     * @notice This method allows a permissioned admin to burn the balance of TNGBL in this contract.
     */
    function burnTngbl() external onlyOwner {
        _burnTngbl();
    }

    /**
     * @notice This method allows a permissioned admin to update the `receiver` state variable.
     */
    function setReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "CrossChainMigrator: Invalid input");
        receiver = _newReceiver;
    }


    // --------------
    // Puglic Methods
    // --------------

    /**
     * @dev Estimates the fees required for migrating tokens to another chain using LayerZero. This function is useful
     * for users to understand the cost of migration before initiating the transaction.
     *
     * @param dstChainId The destination chain ID for the migration.
     * @param toAddress The address on the destination chain to receive the tokens.
     * @param amount The amount of tokens to migrate.
     * @param useZro Indicates whether to use ZRO token for paying fees.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     * @return nativeFee Estimated native token fee for migration.
     * @return zroFee Estimated ZRO token fee for migration, if ZRO is used.
     */
    function estimateMigrateTokensFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        bool useZro,
        bytes calldata adapterParams
    ) public view returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for migrate()
        bytes memory payload = abi.encode(SEND, toAddress, amount);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, useZro, adapterParams);
    }

    /**
     * @dev Estimates the fees required for migrating tokens to another chain using LayerZero. This function is
     * useful for users to understand the cost of migration before initiating the transaction.
     *
     * @param dstChainId The destination chain ID for the migration.
     * @param toAddress The address on the destination chain to receive the tokens.
     * @param lockedAmount The locked amount of the VE token to migrate.
     * @param vestingDuration The vesting duration of the VE token to migrate.
     * @param useZro Indicates whether to use ZRO token for paying fees.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     * @return nativeFee Estimated native token fee for migration.
     * @return zroFee Estimated ZRO token fee for migration, if ZRO is used.
     */
    function estimateMigrateNFTFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 lockedAmount,
        uint256 vestingDuration,
        bool useZro,
        bytes calldata adapterParams
    ) public view returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for migrateVotingEscrow()
        bytes memory payload = abi.encode(SEND_NFT, toAddress, lockedAmount, vestingDuration);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, useZro, adapterParams);
    }

    /**
     * @dev Estimates the fees required for migrating tokens to another chain using LayerZero. This function is
     * useful for users to understand the cost of migration before initiating the transaction.
     *
     * @param dstChainId The destination chain ID for the migration.
     * @param toAddress The address on the destination chain to receive the tokens.
     * @param lockedAmounts Array of locked amounts of the VE token to migrate.
     * @param vestingDurations Array of vesting durations of the VE token to migrate.
     * @param useZro Indicates whether to use ZRO token for paying fees.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     * @return nativeFee Estimated native token fee for migration.
     * @return zroFee Estimated ZRO token fee for migration, if ZRO is used.
     */
    function estimateMigrateNFTFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256[] memory lockedAmounts,
        uint256[] memory vestingDurations,
        bool useZro,
        bytes calldata adapterParams
    ) public view returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for migrateVotingEscrow()
        bytes memory payload = abi.encode(SEND_NFT, toAddress, lockedAmounts, vestingDurations);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, useZro, adapterParams);
    }


    // ----------------
    // Internal Methods
    // ----------------

    function _migrateNFT() internal {

    }

    /**
     * @notice This method burns the TNGBL balance in this contracts.
     */
    function _burnTngbl() internal {
        uint256 amount = tngblToken.balanceOf(address(this));

        tngblToken.approve(address(this), amount);
        tngblToken.burnFrom(address(this), amount);
    }

    /**
     * @dev Internal function to check the adapter parameters for a LayerZero message. It ensures that the parameters
     * are valid and conform to the expected format, based on the contract's settings.
     *
     * This function is crucial for maintaining the integrity and security of the cross-chain migration process. It
     * validates the gas limit and other parameters to prevent misuse or incorrect message formatting.
     *
     * @param dstChainId The destination chain ID for the message.
     * @param pkType The packet type of the message.
     * @param adapterParams The adapter parameters to be validated.
     * @param extraGas Additional gas to be included in the message.
     */
    function _checkAdapterParams(uint16 dstChainId, uint16 pkType, bytes memory adapterParams, uint256 extraGas) internal virtual {
        if (useCustomAdapterParams) {
            _checkGasLimit(dstChainId, pkType, adapterParams, extraGas);
        } else {
            require(adapterParams.length == 0, "CrossChainMigrator: _adapterParams must be empty.");
        }
    }
    
    /**
     * @dev Internal function to handle incoming cross-chain messages. This contract is not designed to receive
     * messages, so any incoming message causes the contract to revert.
     *
     * This function ensures the contract only sends messages and does not process incoming ones, maintaining its
     * intended role as a migrator.
     */
    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory) internal virtual override {
        // Contract should never receive a cross-chain message
        assert(false);
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the DEFAULT_ADMIN_ROLE role to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}