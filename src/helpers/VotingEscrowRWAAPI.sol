// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { RWAVotingEscrow } from "../governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../governance/VotingEscrowVesting.sol";
import { DelegateFactory } from "../governance/DelegateFactory.sol";
import { Delegator } from "../governance/Delegator.sol";
import { RevenueStreamETH } from "../RevenueStreamETH.sol";

contract VotingEscrowRWAAPI is UUPSUpgradeable, AccessControlUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    /// @dev Contract reference for DelegateFactory.
    DelegateFactory public constant delegateFactory = DelegateFactory(0x4Bc715a61dF515944907C8173782ea83d196D0c9);
    /// @dev Contract reference for RWAVotingEscrow.
    RWAVotingEscrow public veRWA;
    /// @dev Contract reference for VotingEscrowVesting.
    VotingEscrowVesting public veVesting;
    /// @dev Contract reference for RevenueStreamETH.
    RevenueStreamETH public revStream;

    /// @dev Object used to return veRWA token data.
    struct TokenData {
        /// @dev Token identifier.
        uint256 tokenId;
        /// @dev Amount of RWA locked in token.
        uint256 lockedAmount;
        /// @dev Remaining duration left to vest until lock expired.
        uint256 remainingDuration;
        /// @dev Voting power of token.
        uint256 votingPower;
    }

    /// @dev Object used to return delegated veRWA token data.
    struct DelegatedTokenData {
        /// @dev Token identifier.
        uint256 tokenId;
        /// @dev Amount of RWA locked in token.
        uint256 lockedAmount;
        /// @dev Remaining duration left to vest until lock expired.
        uint256 remainingDuration;
        /// @dev Voting power of token.
        uint256 votingPower;
        /// @dev Timestamp of when delegation is expected to expire.
        uint256 expirationDate;
        /// @dev Creator of delegation and original owner of NFT.
        address owner;
    }

    /// @dev Object used to return veRWA vesting data.
    struct VestingData {
        /// @dev Token identifier.
        uint256 tokenId;
        /// @dev lock epoch start time.
        uint256 startTime;
        /// @dev lock epoch end time.
        uint256 endTime;
        ///@dev amount of tokens locked.
        uint256 amount;
    }


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
     * @param _veRWA Contract address of RWAVotingEscrow.
     * @param _veVesting Contract address for VotingEscrowVesting.
     * @param _revStream Contract address for RevenueStreamETH.
     */
    function initialize(
        address _admin,
        address _veRWA,
        address _veVesting,
        address _revStream
    ) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        veRWA = RWAVotingEscrow(_veRWA);
        veVesting = VotingEscrowVesting(_veVesting);
        revStream = RevenueStreamETH(payable(_revStream));
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice Returns current tokenId of RWAVotingEscrow tokens.
     */
    function getTokenId() external view returns (uint256) {
        return veRWA.getTokenId();
    }

    // ~ balances & supply ~

    /**
     * @notice Returns the balance of RWAVotingEscrow NFTs of a single account.
     * @param account Address of account we wish to fetch balance of.
     * @return balance Amount of NFTs in custody of `account`.
     */
    function getNFTBalanceOf(address account) external view returns (uint256 balance) {
        return veRWA.balanceOf(account);
    }

    /**
     * @notice Returns an array of tokenIds owned by an address.
     * @param account Address of account we wish to fetch array of NFTs in custody of.
     * @return tokenIds Array of tokenIds owned by `account`.
     */
    function getNFTsOfOwner(address account) external view returns (uint256[] memory tokenIds) {
        uint256 amount = veRWA.balanceOf(account);
        tokenIds = new uint256[](amount);

        for (uint256 i; i < amount;) {
            tokenIds[i] = veRWA.tokenOfOwnerByIndex(account, i);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns an array of tokenIds owned by an address. It also returns the locked amount of RWA and remaining duration of each NFT.
     * @param account Address of account we wish to fetch array of NFTs in custody of.
     * @return tokenData Array of token data.
     */
    function getNFTsOfOwnerWithData(address account) external view returns (TokenData[] memory tokenData) {
        uint256 amount = veRWA.balanceOf(account);
        tokenData = new TokenData[](amount);

        for (uint256 i; i < amount;) {
            uint256 tokenId = veRWA.tokenOfOwnerByIndex(account, i);
            tokenData[i] = TokenData({
                tokenId: tokenId,
                lockedAmount: veRWA.getLockedAmount(tokenId),
                remainingDuration: veRWA.getRemainingVestingDuration(tokenId),
                votingPower: veRWA.getPastVotingPower(tokenId, block.timestamp-1)
            });
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns an array of tokenIds (with extensive data) that are delegated to an addrres.
     * @param account Address of account we wish to query delegation data for (if any).
     * @return tokenData Array of delegated token data that's delegated to `account`.
     * @return num Length of tokenData.
     */
    function getDelegatedNFTsByAccountWithData(address account) external view returns (DelegatedTokenData[] memory tokenData, uint256 num) {
        // grab all delegators
        address[] memory delegators = delegateFactory.getDelegatorsArray();
        tokenData = new DelegatedTokenData[](delegators.length);

        // loop through delegators and return any tokens that are delegated to account
        for (uint256 i; i < delegators.length;) {
            Delegator delegator = Delegator(delegators[i]);
            if (delegator.delegatee() == account) {
                uint256 tokenId = delegator.delegatedToken();
                tokenData[num] = DelegatedTokenData({
                    tokenId: tokenId,
                    lockedAmount: veRWA.getLockedAmount(tokenId),
                    remainingDuration: veRWA.getRemainingVestingDuration(tokenId),
                    votingPower: veRWA.getPastVotingPower(tokenId, block.timestamp-1),
                    expirationDate: delegateFactory.delegatorExpiration(address(delegator)),
                    owner: delegator.creator()
                });
                unchecked {
                    ++num;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns the total supply of RWAVotingEscrow NFTs.
     */
    function getNFTTotalSupply() external view returns (uint256) {
        return veRWA.totalSupply();
    }

    /**
     * @notice Returns an array of all RWAVotingEscrow tokenIds in circulation.
     */
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

    /**
     * @notice Returns the amount of $RWA tokens locked in specified RWAVotingEscrow NFT.
     * @param tokenId Token identifier of token with locked $RWA.
     */
    function getLockedAmount(uint256 tokenId) external view returns (uint256) {
        return veRWA.getLockedAmount(tokenId);
    }

    /**
     * @notice Returns the timestamp a specified RWAVotingEscrow NFT was minted.
     * @param tokenId Token identifier of token with locked $RWA.
     */
    function getMintingTimestamp(uint256 tokenId) external view returns (uint256) {
        return veRWA.getMintingTimestamp(tokenId);
    }

    /**
     * @notice Returns the remaining vesting duration until lock end time is reached (in seconds).
     * @param tokenId Token identifier of token with locked $RWA.
     */
    function getRemainingVestingDuration(uint256 tokenId) external view returns (uint256) {
        return veRWA.getRemainingVestingDuration(tokenId);
    }

    // ~ vesting data ~

    /**
     * @notice Returns the vesting schedule data of a given token.
     * @param tokenId Token identifier of token with locked $RWA.
     */
    function getVestingSchedule(uint256 tokenId) external view returns (VotingEscrowVesting.VestingSchedule memory) {
        return veVesting.getSchedule(tokenId);
    }

    /**
     * @notice Returns the amount of RWAVotingEscrow NFTs are being actively vested by a single owner.
     * @param account EOA with NFTs being vested.
     */
    function getAmountTokensVestedByOwner(address account) external view returns (uint256) {
        return veVesting.balanceOf(account);
    }

    /**
     * @notice Returns an array of RWAVotingEscrow NFTs that are being actively vested by a single owner.
     * @param account EOA with NFTs being vested.
     */
    function getVestedTokensByOwner(address account) external view returns (uint256[] memory) {
        return veVesting.getDepositedTokens(account);
    }

    /**
     * @notice Returns an array of tokenIds owned by an address that are being vested. It also returns the locked amount of RWA and remaining duration of each NFT.
     * @param account Address of account we wish to fetch array of NFTs being vested.
     * @return vestingSchedules Array of vesting schedules with tokenIds.
     */
    function getVestedTokensByOwnerWithData(address account) external view returns (VestingData[] memory vestingSchedules) {
        uint256 amount = veVesting.balanceOf(account);
        
        uint256[] memory tokenIds = veVesting.getDepositedTokens(account);
        VotingEscrowVesting.VestingSchedule memory vestingObj;

        vestingSchedules = new VestingData[](amount);

        for (uint256 i; i < amount;) {
            vestingObj = veVesting.getSchedule(tokenIds[i]);

            vestingSchedules[i].tokenId = tokenIds[i];
            vestingSchedules[i].startTime = vestingObj.startTime;
            vestingSchedules[i].endTime = vestingObj.endTime;

            unchecked {
                ++i;
            }
        }
    }

    // ~ voting power ~

    /**
     * @notice Returns the current voting power of an account.
     * @dev This method returns voting power of an account with NFTs in posession. Aka this variable is not affected by delegation.
     * @param account EOA with voting power.
     */
    function getAccountVotingPower(address account) external view returns (uint256) {
        return veRWA.getAccountVotingPower(account);
    }

    /**
     * @notice Returns the historical total voting power in circulation at a given timestamp.
     * @param timepoint Historical timestamp we wish to fetch total voting power for.
     */
    function getPastTotalVotingPower(uint256 timepoint) external view returns (uint256) {
        return veRWA.getPastTotalVotingPower(timepoint);
    }

    /**
     * @notice Returns the historical voting power of a specific token at a given timestamp.
     * @param tokenId Token identifier we wish to fetch voting power of.
     * @param timepoint Historical timestamp.
     */
    function getPastVotingPowerForToken(uint256 tokenId, uint256 timepoint) external view returns (uint256) {
        return veRWA.getPastVotingPower(tokenId, timepoint);
    }

    /**
     * @notice Returns the current voting power of an EOA.
     * @dev This method differs from `getAccountVotingPower` because it is affected by delegation.
     *      If Bob delegates voting power to Alice. getVotes(ALICE) will be > 0.
     * @param account EOA with voting power.
     */
    function getVotes(address account) external view returns (uint256) {
        return veRWA.getVotes(account);
    }

    /**
     * @notice Returns historical voting power of an `account`.
     * @param account EOA with voting power.
     * @param timepoint Timestamp we wish to fetch voting power for `account`.
     */
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        return veRWA.getPastVotes(account, timepoint);
    }

    // ~ claimable revenue share ~

    /**
     * @notice Returns amount of ETH that is claimable by `account`.
     * @param account Address with claimable revenue.
     */
    function getClaimable(address account) external view returns (uint256 claimable) {
        (claimable,) = revStream.claimable(account);
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