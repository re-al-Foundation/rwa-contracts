// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

// passive income nft imports
import { PassiveIncomeNFT } from "../src/refs/PassiveIncomeNFT.sol";
import { PassiveIncomeCalculator } from "../src/refs/PassiveIncomeCalculator.sol";

// layerZero imports
import { ILayerZeroEndpoint } from "@layerZero/contracts/interfaces/ILayerZeroEndpoint.sol";

// local imports
import { CrossChainMigrator } from "../src/CrossChainMigrator.sol";
import { RealReceiver } from "../src/RealReceiver.sol";
import { TangibleERC20Mock } from "./utils/TangibleERC20Mock.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { LZEndpointMock } from "./utils/LZEndpointMock.sol";
import { MarketplaceMock } from "./utils/MarketplaceMock.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";

// local helper imports
import "./utils/Utility.sol";
import "./utils/Constants.sol";

/**
 * @title MirgationIntegrationTest
 * @author @chasebrownn
 * @notice This test file contains the basic integration testing for migration contracts.
 */
contract MirgationIntegrationTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    PassiveIncomeNFT public passiveIncomeNFTV1 = PassiveIncomeNFT(POLYGON_PI_NFT);
    PassiveIncomeCalculator public piCalculator = PassiveIncomeCalculator(POLYGON_PI_CALC);
    TangibleERC20Mock public tngblToken = TangibleERC20Mock(POLYGON_TNGBL_TOKEN);
    CrossChainMigrator public migrator;
    RealReceiver public receiver;
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    MarketplaceMock public marketplace;

    // helper
    LZEndpointMock public endpoint;

    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public migratorProxy;
    ERC1967Proxy public receiverProxy;
    ERC1967Proxy public receiverRWAProxy;

    // ~ Variables ~

    uint16 private constant SEND = 0;
    uint16 private constant SEND_NFT = 1;
    uint16 private constant SEND_NFT_BATCH = 2;

    uint256 public amountETH;
    uint8   public durationInMonths;
    uint256 public totalDuration;
    uint256 public amountToLock;
    bytes   public adapterParams;
    uint256 public amountAirdrop;

    function setUp() public {

        vm.createSelectFork(POLYGON_RPC_URL);

        // ~ Deploy Contracts ~

        // Deploy Migration endpoint
        endpoint = new LZEndpointMock(uint16(block.chainid));

        // Deploy Marketplace
        marketplace = new MarketplaceMock();

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN,
                address(0),
                address(0)
            )
        );
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));

        // Deploy vesting contract
        vesting = new VotingEscrowVesting();

        // Deploy proxy for vesting contract
        vestingProxy = new ERC1967Proxy(
            address(vesting),
            abi.encodeWithSelector(VotingEscrowVesting.initialize.selector,
                ADMIN
            )
        );
        vesting = VotingEscrowVesting(address(vestingProxy));

        // Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();

        // Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken),
                address(vesting),
                address(0), // Note: For migration
                ADMIN
            )
        );
        veRWA = RWAVotingEscrow(address(veRWAProxy));

        // Deploy RealReceiver
        receiver = new RealReceiver(address(endpoint));

        // Deploy proxy for receiver
        receiverProxy = new ERC1967Proxy(
            address(receiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(block.chainid),
                address(veRWA),
                address(rwaToken),
                ADMIN
            )
        );
        receiver = RealReceiver(address(receiverProxy));

        // Deploy CrossChainMigrator
        migrator = new CrossChainMigrator(address(endpoint));

        // Deploy proxy for migrator
        migratorProxy = new ERC1967Proxy(
            address(migrator),
            abi.encodeWithSelector(CrossChainMigrator.initialize.selector,
                address(passiveIncomeNFTV1), // LOCAL ADDRESS 1 -> 3,3+ NFT
                address(piCalculator),
                address(tngblToken), // LOCAL ADDRESS 2 -> $TNGBL
                address(receiver), // REMOTE ADDRESS 1 -> RECEIVER for NFT
                uint16(block.chainid), // REMOTE CHAIN ID
                ADMIN
            )
        );
        migrator = CrossChainMigrator(address(migratorProxy));

        // ~ Config ~

        // set dest pair -> receiverNFT/polygonEndpoint
        endpoint.setDestLzEndpoint(address(receiver), address(endpoint));

        // add receiver endpoint address to veRWA
        vm.prank(ADMIN);
        veRWA.updateEndpointReceiver(address(receiver));

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // set marketplace on PassiveIncomeNFT
        //passiveIncomeNFTV1.setMarketplaceContract(address(marketplace));

        vm.startPrank(ADMIN);
        migrator.setMinDstGas(uint16(block.chainid), SEND, 200000);
        migrator.setMinDstGas(uint16(block.chainid), SEND_NFT, 200000);
        migrator.setMinDstGas(uint16(block.chainid), SEND_NFT_BATCH, 200000);
        migrator.setTrustedRemoteAddress(uint16(block.chainid), abi.encodePacked(address(receiver)));
        receiver.setTrustedRemoteAddress(uint16(block.chainid), abi.encodePacked(address(migrator)));
        vm.stopPrank();

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(receiver));
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADMIN_TNGBL);
        tngblToken.grantRole(MINTER_ROLE, address(this));
        tngblToken.grantRole(BURNER_ROLE, address(migrator));
        vm.stopPrank();

        // Exclude necessary addresses from RWA fees.
        vm.startPrank(ADMIN);
        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(JOE, true);
        vm.stopPrank();

        // Mint Joe $RWA tokens
        //rwaToken.mintFor(JOE, 1_000 ether);
        deal(address(rwaToken), JOE, 1_000 ether);

        // begin migration
        vm.prank(ADMIN);
        migrator.toggleMigration();

        vm.pauseGasMetering();
    }


    // -------
    // Utility
    // -------

    /// @dev Internal helper method for minting $TNGBL tokens.
    function _mintTngblTokens(address _recipient, uint256 _amount) internal {
        uint256 preBal = tngblToken.balanceOf(_recipient);

        //vm.prank(DEFAULT_ADMIN_TNGBL);
        tngblToken.mintFor(_recipient, _amount);
        //address(tngblToken).call(abi.encodeWithSignature("mintFor(address,uint256)", _recipient, _amount));

        assertEq(tngblToken.balanceOf(_recipient), preBal + _amount);
    }

    /// @dev Internal helper method for minting PI NFTs.
    function _mintPassiveIncomeNFT(address _recipient, uint256 _lockedAmount, uint8 _durationInMonths) internal returns (uint256 tokenId) {
        _mintTngblTokens(_recipient, _lockedAmount);
        uint256 preBal = passiveIncomeNFTV1.balanceOf(_recipient);

        vm.startPrank(_recipient);
        tngblToken.approve(address(passiveIncomeNFTV1), _lockedAmount);
        tokenId = passiveIncomeNFTV1.mint(_recipient, _lockedAmount, _durationInMonths, false, false);
        vm.stopPrank();

        assertEq(passiveIncomeNFTV1.balanceOf(_recipient), preBal + 1);
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_migrator_integration_init_state() public {
        assertEq(tngblToken.hasRole(BURNER_ROLE, address(migrator)), true);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @notice Verifies proper state changes when CrossChainMigrator::migrateNFT is executed.
    function test_migrator_integration_migrateNFT_single() public {
        
        // ~ Config ~

        amountToLock = 1_000 ether;
        durationInMonths = 10; // months
        totalDuration = (uint256(durationInMonths) * 30 days);
        uint256 tokenId = _mintPassiveIncomeNFT(JOE, amountToLock, durationInMonths);

        (uint256 startTime,
        uint256 endTime,
        uint256 lockedAmount,
        uint256 multiplier,
        /** claimed */,
        uint256 maxPayout) = passiveIncomeNFTV1.locks(tokenId);

        emit log_named_uint("locked amount", lockedAmount);
        emit log_named_uint("mul", multiplier);
        emit log_named_uint("max payout", maxPayout);

        // create adapterParams for custom gas.
        adapterParams = abi.encodePacked(uint16(1), uint256(200000));

        // get quote for fees
        (amountETH,) = migrator.estimateMigrateNFTFee(
            uint16(block.chainid),
            abi.encodePacked(JOE),
            lockedAmount + maxPayout,
            endTime - startTime,
            false,
            adapterParams
        );

        uint256 votingPower = (lockedAmount + maxPayout).calculateVotingPower(totalDuration);

        vm.deal(JOE, amountETH);

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 veRWATokenId = veRWA.getTokenId();
        ++veRWATokenId;

        uint256 preSupply = rwaToken.totalSupply();

        // ~ Pre-state check ~

        // v1
        assertEq(passiveIncomeNFTV1.ownerOf(tokenId), JOE);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + totalDuration);
        assertEq(lockedAmount, amountToLock);

        // v2
        assertEq(veRWA.totalSupply(), 0);
        assertEq(rwaToken.totalSupply(), preSupply);

        // ~ Execute migrateNFT ~

        emit log_address(passiveIncomeNFTV1.ownerOf(tokenId));

        vm.startPrank(JOE);
        passiveIncomeNFTV1.approve(address(migrator), tokenId);
        migrator.migrateNFT{value:amountETH}(
            tokenId,
            JOE,
            payable(JOE),
            address(0),
            adapterParams
        );
        vm.stopPrank();

        // ~ Post-state check ~

        // v1
        assertEq(passiveIncomeNFTV1.ownerOf(tokenId), address(migrator));

        // v2
        assertEq(veRWA.totalSupply(), 1);
        assertEq(veRWA.ownerOf(veRWATokenId), JOE);
        assertEq(rwaToken.balanceOf(address(veRWA)), lockedAmount + maxPayout);
        assertEq(rwaToken.totalSupply(), preSupply + lockedAmount + maxPayout);
        
        assertEq(veRWA.getLockedAmount(veRWATokenId), lockedAmount + maxPayout);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(veRWATokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, votingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, votingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(veRWATokenId), totalDuration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), votingPower);
    }

    /// @notice Verifies proper state changes when CrossChainMigrator::migrateNFTBatch is executed.
    function test_migrator_integration_migrateNFTBatch() public {

        // ~ Config ~

        uint256 numTokens = 10;
        amountToLock = 1_000 ether;
        durationInMonths = 10; // months
        totalDuration = (uint256(durationInMonths) * 30 days);

        uint256[] memory tokenIds = new uint256[](numTokens);
        uint256[] memory lockedAmounts = new uint256[](numTokens);
        uint256[] memory durations = new uint256[](numTokens);

        uint256[] memory startTime = new uint256[](numTokens);
        uint256[] memory endTime = new uint256[](numTokens);
        uint256[] memory lockedAmount = new uint256[](numTokens);
        uint256[] memory maxPayout = new uint256[](numTokens);

        for (uint256 i; i < numTokens; ++i) {
            tokenIds[i] = _mintPassiveIncomeNFT(JOE, amountToLock, durationInMonths);

            (startTime[i],
            endTime[i],
            lockedAmount[i],
            /** multiplier */,
            /** claimed */,
            maxPayout[i]) = passiveIncomeNFTV1.locks(tokenIds[i]);

            lockedAmounts[i] = lockedAmount[i] + maxPayout[i];
            durations[i] = endTime[i] - startTime[i];
        }

        // create adapterParams for custom gas.
        adapterParams = abi.encodePacked(uint16(1), uint256(200000));

        // get quote for fees
        (amountETH,) = migrator.estimateMigrateNFTFee(
            uint16(block.chainid),
            abi.encodePacked(JOE),
            lockedAmounts,
            durations,
            false,
            adapterParams
        );

        uint256 votingPower = (lockedAmount[0] + maxPayout[0]).calculateVotingPower(totalDuration);

        vm.deal(JOE, amountETH);

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 veRWATokenId = veRWA.getTokenId();
        uint256 preSupply = rwaToken.totalSupply();

        // ~ Pre-state check ~

        // v1
        for (uint256 i; i < numTokens; ++i) {
            assertEq(passiveIncomeNFTV1.ownerOf(tokenIds[i]), JOE);
            assertEq(startTime[i], block.timestamp);
            assertEq(endTime[i], block.timestamp + totalDuration);
            assertEq(lockedAmount[i], amountToLock);
        }

        // v2
        assertEq(veRWA.totalSupply(), 0);
        assertEq(veRWA.balanceOf(JOE), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(rwaToken.totalSupply(), preSupply);

        // ~ Execute migrateNFT ~

        vm.startPrank(JOE);
        for (uint256 i; i < numTokens; ++i) {
            passiveIncomeNFTV1.approve(address(migrator), tokenIds[i]);
        }
        migrator.migrateNFTBatch{value:amountETH}(
            tokenIds,
            JOE,
            payable(JOE),
            address(0),
            adapterParams
        );
        vm.stopPrank();

        // ~ Post-state check ~

        for (uint256 i; i < numTokens; ++i) {      
            // v1
            assertEq(passiveIncomeNFTV1.ownerOf(tokenIds[i]), address(migrator));

            // v2
            assertEq(veRWA.getLockedAmount(++veRWATokenId), lockedAmount[i] + maxPayout[i]);
            // get voting power checkpoints for token
            votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(veRWATokenId);
            assertEq(votingPowerCheckpoints._checkpoints.length, 1);
            assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
            assertEq(votingPowerCheckpoints._checkpoints[0]._value, votingPower);

            // get total voting power checkpoints
            totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
            assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, votingPower * numTokens);

            // check remaining vesting duration for token
            assertEq(veRWA.getRemainingVestingDuration(veRWATokenId), totalDuration);

            assertEq(veRWA.ownerOf(veRWATokenId), JOE);
        }

        assertEq(rwaToken.balanceOf(address(veRWA)), (lockedAmount[0] + maxPayout[0]) * numTokens);
        assertEq(rwaToken.totalSupply(), preSupply + ((lockedAmount[0] + maxPayout[0]) * numTokens));
        
        assertEq(veRWA.totalSupply(), numTokens);
        assertEq(veRWA.balanceOf(JOE), numTokens);
        
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), votingPower * numTokens);

        emit log_named_uint("Gas needed", amountETH); // ~0.01321 ETH
    }

    /// @notice Verifies proper state changes when CrossChainMigrator::migrateTokens is executed.
    function test_migrator_integration_migrateTokens() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        _mintTngblTokens(JOE, amountTokens);

        // airdrop Alice with adapterParams
        adapterParams = abi.encodePacked(uint16(2), uint256(200000), amountAirdrop, ALICE);

        (amountETH,) = migrator.estimateMigrateTokensFee(
            uint16(block.chainid),
            abi.encodePacked(JOE),
            amountTokens,
            false,
            adapterParams
        );

        vm.deal(JOE, amountETH);

        uint256 preBal = rwaToken.balanceOf(JOE);
        //uint256 preSupplyTngbl = tngblToken.totalSupply();

        // ~ Pre-state check ~

        assertEq(tngblToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(JOE), preBal);

        // ~ Execute migrateNFT ~

        vm.startPrank(JOE);
        tngblToken.approve(address(migrator), amountTokens);
        migrator.migrateTokens{value:amountETH}(
            amountTokens,
            JOE,
            payable(JOE),
            address(0),
            adapterParams
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(tngblToken.balanceOf(JOE), 0);
        assertEq(tngblToken.balanceOf(address(migrator)), amountTokens);
        //assertEq(tngblToken.totalSupply(), preSupplyTngbl - amountTokens);
        assertEq(rwaToken.balanceOf(JOE), preBal + amountTokens);
    }

    /// @notice Verifies the usage of Layer Zero's advanced adapter params settings allowing
    ///         us to airdrop native ETH to our migrators on the destination chain.
    function test_migrator_integration_migrateNFT_airdrop() public {

        // ~ Config ~

        amountToLock = 1_000 ether;
        durationInMonths = 10; // months
        totalDuration = (uint256(durationInMonths) * 30 days);
        uint256 tokenId = _mintPassiveIncomeNFT(JOE, amountToLock, durationInMonths);

        amountAirdrop = 2 ether;

        (uint256 startTime,
        uint256 endTime,
        uint256 lockedAmount,
        /** multiplier */,
        /** claimed */,
        uint256 maxPayout) = passiveIncomeNFTV1.locks(tokenId);

        // airdrop Alice with adapterParams
        adapterParams = abi.encodePacked(uint16(2), uint256(200000), amountAirdrop, ALICE);

        // get quote for fees
        (amountETH,) = migrator.estimateMigrateNFTFee(
            uint16(block.chainid),
            abi.encodePacked(JOE),
            lockedAmount + maxPayout,
            endTime - startTime,
            false,
            adapterParams
        );
        emit log_named_uint("quoted", amountETH);

        vm.deal(JOE, amountETH);

        // ~ Pre-state check ~

        assertEq(address(JOE).balance, amountETH);
        assertEq(address(ALICE).balance, 0);

        // ~ Execute migrateNFT ~

        vm.startPrank(JOE);
        passiveIncomeNFTV1.approve(address(migrator), tokenId);
        migrator.migrateNFT{value:amountETH}(
            tokenId,
            JOE,
            payable(JOE),
            address(0),
            adapterParams
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(address(JOE).balance, 0);
        assertEq(address(ALICE).balance, amountAirdrop);
    }

    /// @notice Verifies the usage of Layer Zero's advanced adapter params settings allowing
    ///         us to airdrop native ETH to our migrators on the destination chain.
    function test_migrator_integration_migrateNFTBatch_airdrop() public {
        // ~ Config ~

        uint256 numTokens = 10;
        amountToLock = 1_000 ether;
        durationInMonths = 10; // months
        totalDuration = (uint256(durationInMonths) * 30 days);

        uint256[] memory tokenIds = new uint256[](numTokens);
        uint256[] memory lockedAmounts = new uint256[](numTokens);
        uint256[] memory durations = new uint256[](numTokens);

        uint256[] memory startTime = new uint256[](numTokens);
        uint256[] memory endTime = new uint256[](numTokens);
        uint256[] memory lockedAmount = new uint256[](numTokens);
        uint256[] memory maxPayout = new uint256[](numTokens);

        amountAirdrop = 2 ether;

        for (uint256 i; i < numTokens; ++i) {
            tokenIds[i] = _mintPassiveIncomeNFT(JOE, amountToLock, durationInMonths);

            (startTime[i],
            endTime[i],
            lockedAmount[i],
            /** multiplier */,
            /** claimed */,
            maxPayout[i]) = passiveIncomeNFTV1.locks(tokenIds[i]);

            lockedAmounts[i] = lockedAmount[i] + maxPayout[i];
            durations[i] = endTime[i] - startTime[i];
        }

        // airdrop Alice with adapterParams
        adapterParams = abi.encodePacked(uint16(2), uint256(200000), amountAirdrop, ALICE);

        // get quote for fees
        (amountETH,) = migrator.estimateMigrateNFTFee(
            uint16(block.chainid),
            abi.encodePacked(JOE),
            lockedAmounts,
            durations,
            false,
            adapterParams
        );

        uint256 votingPower = (lockedAmount[0] + maxPayout[0]).calculateVotingPower(totalDuration);

        vm.deal(JOE, amountETH);

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 veRWATokenId = veRWA.getTokenId();
        uint256 preSupply = rwaToken.totalSupply();

        // ~ Pre-state check ~

        // v1
        for (uint256 i; i < numTokens; ++i) {
            assertEq(passiveIncomeNFTV1.ownerOf(tokenIds[i]), JOE);
            assertEq(startTime[i], block.timestamp);
            assertEq(endTime[i], block.timestamp + totalDuration);
            assertEq(lockedAmount[i], amountToLock);
        }

        // v2
        assertEq(veRWA.totalSupply(), 0);
        assertEq(veRWA.balanceOf(JOE), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(rwaToken.totalSupply(), preSupply);

        assertEq(address(JOE).balance, amountETH);
        assertEq(address(ALICE).balance, 0);

        // ~ Execute migrateNFT ~

        vm.startPrank(JOE);
        for (uint256 i; i < numTokens; ++i) {
            passiveIncomeNFTV1.approve(address(migrator), tokenIds[i]);
        }
        migrator.migrateNFTBatch{value:amountETH}(
            tokenIds,
            JOE,
            payable(JOE),
            address(0),
            adapterParams
        );
        vm.stopPrank();

        // ~ Post-state check ~

        for (uint256 i; i < numTokens; ++i) {      
            // v1
            assertEq(passiveIncomeNFTV1.ownerOf(tokenIds[i]), address(migrator));

            // v2
            assertEq(veRWA.getLockedAmount(++veRWATokenId), lockedAmount[i] + maxPayout[i]);
            // get voting power checkpoints for token
            votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(veRWATokenId);
            assertEq(votingPowerCheckpoints._checkpoints.length, 1);
            assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
            assertEq(votingPowerCheckpoints._checkpoints[0]._value, votingPower);

            // get total voting power checkpoints
            totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
            assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, votingPower * numTokens);

            // check remaining vesting duration for token
            assertEq(veRWA.getRemainingVestingDuration(veRWATokenId), totalDuration);

            assertEq(veRWA.ownerOf(veRWATokenId), JOE);
        }

        assertEq(rwaToken.balanceOf(address(veRWA)), (lockedAmount[0] + maxPayout[0]) * numTokens);
        assertEq(rwaToken.totalSupply(), preSupply + ((lockedAmount[0] + maxPayout[0]) * numTokens));
        
        assertEq(veRWA.totalSupply(), numTokens);
        assertEq(veRWA.balanceOf(JOE), numTokens);
        
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), votingPower * numTokens);

        assertEq(address(JOE).balance, 0);
        assertEq(address(ALICE).balance, amountAirdrop);

        emit log_named_uint("Gas needed", amountETH); // ~0.01321 ETH
    }

    /// @notice Verifies the usage of Layer Zero's advanced adapter params settings allowing
    ///         us to airdrop native ETH to our migrators on the destination chain.
    function test_migrator_integration_migrateTokens_airdrop() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        _mintTngblTokens(JOE, amountTokens);

        amountAirdrop = 2 ether;

        // airdrop Alice with adapterParams
        adapterParams = abi.encodePacked(uint16(2), uint256(200000), amountAirdrop, ALICE);
        
        (amountETH,) = migrator.estimateMigrateTokensFee(
            uint16(block.chainid),
            abi.encodePacked(JOE),
            amountTokens,
            false,
            adapterParams
        );
        emit log_named_uint("quoted", amountETH);

        vm.deal(JOE, amountETH);

        uint256 preBal = rwaToken.balanceOf(JOE);
        //uint256 preSupplyTngbl = tngblToken.totalSupply();

        // ~ Pre-state check ~

        assertEq(tngblToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(JOE), preBal);

        assertEq(address(JOE).balance, amountETH);
        assertEq(address(ALICE).balance, 0);

        // ~ Execute migrateNFT ~

        vm.startPrank(JOE);
        tngblToken.approve(address(migrator), amountTokens);
        migrator.migrateTokens{value:amountETH}(
            amountTokens,
            JOE,
            payable(JOE),
            address(0),
            adapterParams
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(tngblToken.balanceOf(JOE), 0);
        assertEq(tngblToken.balanceOf(address(migrator)), amountTokens);
        //assertEq(tngblToken.totalSupply(), preSupplyTngbl - amountTokens);
        assertEq(rwaToken.balanceOf(JOE), preBal + amountTokens);

        assertEq(address(JOE).balance, 0);
        assertEq(address(ALICE).balance, amountAirdrop);
    }
}