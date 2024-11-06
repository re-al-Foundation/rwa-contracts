// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RewardEscrow } from "../../../src/points/RewardEscrow.sol";
import { DelegateFactory } from "../../../src/governance/DelegateFactory.sol";
import { RWAToken } from "../../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";

// local helper imports
import "../../utils/Utility.sol";
import "../../utils/Constants.sol";

/**
 * @title RewardEscrowTestUtility
 * @author @chasebrownn
 * @notice This acts as a Utility file for RewardEscrow Tests.
 */
contract RewardEscrowTestUtility is Utility {

    // ~ Contracts ~

    RewardEscrow public rewardEscrow;

    // rwa contracts
    RWAToken public constant rwaToken = RWAToken(0x4644066f535Ead0cde82D209dF78d94572fCbf14);
    RWAVotingEscrow public constant rwaVotingEscrow = RWAVotingEscrow(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);
    RevenueStreamETH public constant revStream = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);
    RevenueDistributor public constant revDist = RevenueDistributor(payable(0x7a2E4F574C0c28D6641fE78197f1b460ce5E4f6C));

    function setUp() public virtual {
        vm.createSelectFork(REAL_RPC_URL, 716890);

        // ~ Deploy Contracts ~

        // Deploy rewardEscrow & proxy
        ERC1967Proxy rewardEscrowProxy = new ERC1967Proxy(
            address(new RewardEscrow()),
            abi.encodeWithSelector(RewardEscrow.initialize.selector,
                MULTISIG
            )
        );
        rewardEscrow = RewardEscrow(address(rewardEscrowProxy));


        _createLabels();
        _initStateCheck();
    }

    // -------
    // Utility
    // -------

    /// @dev Verifies initial state.
    function _initStateCheck() internal view {
        // TODO
    }

    /// @dev Instantiates labels for all global contracts.
    function _createLabels() internal {
        vm.label(address(rewardEscrow), "rewardEscrow");
        vm.label(address(rwaToken), "RWAToken");
        vm.label(address(rwaVotingEscrow), "RWAVotingEscrow");
        vm.label(address(revStream), "RevenueStreamETH");
    }
}