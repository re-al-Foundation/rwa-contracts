// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { RWAVotingEscrow } from "../governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../governance/VotingEscrowVesting.sol";
import { RevenueStreamETH } from "../RevenueStreamETH.sol";

contract VotingEscrowRWAAPI is UUPSUpgradeable, AccessControlUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    RWAVotingEscrow public veRWA;

    address public rwaToken;

    VotingEscrowVesting public veVesting;

    RevenueStreamETH public revStream;


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice This initializes RWAToken.
     * @param _admin Initial default admin address.
     */
    function initialize(
        address _admin,
        address _veRWA,
        address _veVesting,
        address _rwaToken,
        address _revStream
    ) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        veRWA = RWAVotingEscrow(_veRWA);
        rwaToken = _rwaToken;
        veVesting = VotingEscrowVesting(_veVesting);
        revStream = RevenueStreamETH(payable(_revStream));
    }


    // ----------------
    // External Methods
    // ----------------

    function getTokenId() external view returns (uint256 tokenId) {
        tokenId = veRWA.getTokenId();
    }

    // ~ balances & supply ~

    function getNFTBalanceOf(address account) external view returns (uint256 balance) {
        return veRWA.balanceOf(account);
    }

    function getNFTsOfOwner(address account) external view returns (uint256[] memory tokenIds, uint256 amount) {
        amount = veRWA.balanceOf(account);
        tokenIds = new uint256[](amount);

        for (uint256 i; i < amount;) {
            tokenIds[i] = veRWA.tokenOfOwnerByIndex(account, i);
            unchecked {
                ++i;
            }
        }
    }

    function getNFTTotalSupply() external view returns (uint256 totalSupply) {
        totalSupply = veRWA.totalSupply();
    }

    function getAllNFTs() external view returns (uint256[] memory allTokens) {
        uint256 amount = veRWA.totalSupply();
        allTokens = new uint256[](amount);

        for (uint256 i; i < amount;) {
            allTokens[i] = veRWA.tokenByIndex(i);
            unchecked {
                ++i;
            }
        }
    }

    // ~ lock data ~

    function getLockedAmount(uint256 tokenId) external view returns (uint256) {
        return veRWA.getLockedAmount(tokenId);
    }

    function getMintingTimestamp(uint256 tokenId) external view returns (uint256) {
        return veRWA.getMintingTimestamp(tokenId);
    }

    function getRemainingVestingDuration(uint256 tokenId) external view returns (uint256) {
        return veRWA.getRemainingVestingDuration(tokenId);
    }

    // ~ voting power ~

    function getAccountVotingPower(address account) external view returns (uint256) {
        return veRWA.getAccountVotingPower(account);
    }

    function getPastTotalVotingPower(uint256 timepoint) external view returns (uint256) {
        return veRWA.getPastTotalVotingPower(timepoint);
    }

    function getPastVotingPowerForToken(uint256 tokenId, uint256 timepoint) external view returns (uint256) {
        return veRWA.getPastVotingPower(tokenId, timepoint);
    }

    function getVotes(address account) external view returns (uint256) {
        return veRWA.getVotes(account);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        return veRWA.getPastVotes(account, timepoint);
    }

    // ~ claimable revenue share ~

    function getClaimable(address account) external view returns (uint256 claimable) {
        claimable = revStream.claimable(account);
    }
    
    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

}