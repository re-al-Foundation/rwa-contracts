// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// local imports
// token
import { RWAToken } from "../../../src/RWAToken.sol";
import { RoyaltyHandler } from "../../../src/RoyaltyHandler.sol";
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
// governance
import { VotingEscrowVesting } from "../../../src/governance/VotingEscrowVesting.sol";
import { DelegateFactory } from "../../../src/governance/DelegateFactory.sol";
// revenue management
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";
import { RevenueStream } from "../../../src/RevenueStream.sol";
// migration
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";
import { RealReceiver } from "../../../src/RealReceiver.sol";
// periphery
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/write/mainnet/TransferOwnership.s.sol:TransferOwnership --broadcast --legacy --gas-estimate-multiplier 600 -vvvv
*/

/**
 * @title TransferOwnership
 * @author Chase Brown
 * @notice This script transfers ownership of all on-chain contracts
 */
contract TransferOwnership is DeployUtility {

    // ~ Contracts ~

    // contracts
    RWAVotingEscrow public veRWA;
    RWAToken public rwaToken;
    RoyaltyHandler public royaltyHandler;
    VotingEscrowVesting public vesting;
    DelegateFactory public delegateFactory;
    RevenueDistributor public revDistributor;
    RevenueStreamETH public revStreamETH;
    RevenueStream public revStreamRWA;
    RealReceiver public receiver;
    VotingEscrowRWAAPI public api;

    // ~ Variables ~

    address constant public NEW_OWNER = REAL_MULTISIG;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");
    address public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        _setUp("re.al");
        rwaToken = RWAToken(_loadDeploymentAddress("RWAToken"));
        vesting = VotingEscrowVesting(_loadDeploymentAddress("VotingEscrowVesting"));
        veRWA = RWAVotingEscrow(_loadDeploymentAddress("RWAVotingEscrow"));
        receiver = RealReceiver(_loadDeploymentAddress("RealReceiver"));
        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
        royaltyHandler = RoyaltyHandler(_loadDeploymentAddress("RoyaltyHandler"));
        revStreamETH = RevenueStreamETH(_loadDeploymentAddress("RevenueStreamETH"));
        revStreamRWA = RevenueStream(_loadDeploymentAddress("RevenueStreamRWA"));
        delegateFactory = DelegateFactory(_loadDeploymentAddress("DelegateFactory"));
        api = VotingEscrowRWAAPI(_loadDeploymentAddress("API"));
    }

    function run() public {
        vm.createSelectFork(REAL_RPC_URL);
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        require(NEW_OWNER != address(0));
        console.log(NEW_OWNER);

        receiver.transferOwnership(NEW_OWNER);
        require(receiver.owner() == NEW_OWNER);

        revDistributor.transferOwnership(NEW_OWNER); /// @dev 2step
        require(revDistributor.pendingOwner() == NEW_OWNER);

        revStreamRWA.transferOwnership(NEW_OWNER); /// @dev 2step
        require(revStreamRWA.pendingOwner() == NEW_OWNER);

        revStreamETH.transferOwnership(NEW_OWNER); /// @dev 2step
        require(revStreamETH.pendingOwner() == NEW_OWNER);

        royaltyHandler.transferOwnership(NEW_OWNER); /// @dev 2step
        require(royaltyHandler.pendingOwner() == NEW_OWNER);

        rwaToken.transferOwnership(NEW_OWNER); /// @dev 2step
        require(rwaToken.pendingOwner() == NEW_OWNER);

        delegateFactory.transferOwnership(NEW_OWNER); /// @dev 2step
        require(delegateFactory.pendingOwner() == NEW_OWNER);

        veRWA.transferOwnership(NEW_OWNER); /// @dev 2step
        require(veRWA.pendingOwner() == NEW_OWNER);

        vesting.transferOwnership(NEW_OWNER); /// @dev 2step
        require(vesting.pendingOwner() == NEW_OWNER);

        api.grantRole(DEFAULT_ADMIN_ROLE, NEW_OWNER);
        require(api.hasRole(DEFAULT_ADMIN_ROLE, NEW_OWNER));

        api.revokeRole(DEFAULT_ADMIN_ROLE, DEPLOYER_ADDRESS);
        require(!api.hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER_ADDRESS));

        vm.stopBroadcast();
    }
}