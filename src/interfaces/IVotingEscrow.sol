// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IVotingEscrow Interface
 * @author SeaZarrgh
 * @dev IVotingEscrow interface defines the standard functions for a voting escrow contract, extending the IERC721
 * interface for NFT functionality. It focuses on token locking mechanisms where locking tokens grants users voting
 * power in governance decisions. The interface includes functions for token locking, voting power calculation, and
 * token lifecycle management.
 */
interface IVotingEscrow is IERC721 {
    /**
     * @dev Returns the maximum duration for which tokens can be locked in the voting escrow system. This duration
     * affects the calculation of voting power.
     * @return The maximum time (in seconds) tokens can be locked to accrue voting power.
     */
    function MAX_VESTING_DURATION() external view returns (uint256);

    /**
     * @dev Provides the address of the ERC20 token used in the voting escrow system. Tokens of this type are locked to
     * accrue voting power.
     * @return The ERC20 token contract address used for locking.
     */
    function getLockedToken() external view returns (IERC20);

    /**
     * @dev Retrieves the amount of tokens locked in a specific VotingEscrow token.
     * @param tokenId The identifier of the VotingEscrow token.
     * @return The amount of tokens locked in the specified VotingEscrow token.
     */
    function getLockedAmount(uint256 tokenId) external view returns (uint256);

    /**
     * @dev Gets the timestamp when a specific VotingEscrow token was minted.
     * @param tokenId The identifier of the VotingEscrow token.
     * @return The Unix timestamp marking the minting time of the token.
     */
    function getMintingTimestamp(uint256 tokenId) external view returns (uint256);

    /**
     * @dev Retrieves the total voting power of all tokens at a specific past timepoint.
     * @param timepoint The Unix timestamp for which the total voting power is queried.
     * @return The total voting power at the given timepoint.
     */
    function getPastTotalVotingPower(uint256 timepoint) external view returns (uint256);

    /**
     * @dev Fetches the voting power of a specific VotingEscrow token at a past timepoint.
     * @param tokenId The identifier of the VotingEscrow token.
     * @param timepoint The Unix timestamp for which the voting power is queried.
     * @return The voting power of the specified token at the given timepoint.
     */
    function getPastVotingPower(uint256 tokenId, uint256 timepoint) external view returns (uint256);

    /**
     * @dev Determines the remaining vesting duration for a specific VotingEscrow token.
     * @param tokenId The identifier of the VotingEscrow token.
     * @return The remaining time (in seconds) until the token's lock expires.
     */
    function getRemainingVestingDuration(uint256 tokenId) external view returns (uint256);

    /**
     * @dev Mints a new VotingEscrow token with a specified amount of locked tokens and vesting duration.
     * @param receiver The address to receive the newly minted VotingEscrow token.
     * @param lockedBalance The amount of tokens to lock.
     * @param vestingDuration The duration for which the tokens will be locked.
     * @return tokenId The identifier of the newly minted VotingEscrow token.
     */
    function mint(address receiver, uint208 lockedBalance, uint256 vestingDuration) external returns (uint256);

    /**
     * @dev Burns a specific VotingEscrow token, releasing the locked tokens to the specified receiver.
     * @param receiver The address to receive the unlocked tokens.
     * @param tokenId The identifier of the VotingEscrow token to be burned.
     */
    function burn(address receiver, uint256 tokenId) external;

    /**
     * @dev Deposits additional tokens to an existing VotingEscrow token, increasing the locked balance.
     * @param tokenId The identifier of the VotingEscrow token for the deposit.
     * @param amount The amount of tokens to be added to the locked balance.
     */
    function depositFor(uint256 tokenId, uint256 amount) external;

    /**
     * @dev Merges two VotingEscrow tokens into one, combining their locked balances and possibly affecting their voting
     * power.
     * @param tokenId The identifier of the source VotingEscrow token to be merged.
     * @param intoTokenId The identifier of the target VotingEscrow token to merge into.
     */
    function merge(uint256 tokenId, uint256 intoTokenId) external;

    /**
     * @dev Splits a VotingEscrow token into multiple tokens based on specified share proportions.
     * @param tokenId The identifier of the VotingEscrow token to be split.
     * @param shares An array of proportions for dividing the token.
     * @return tokenIds An array of identifiers for the newly created VotingEscrow tokens.
     */
    function split(uint256 tokenId, uint256[] calldata shares) external returns (uint256[] memory tokenIds);

    /**
     * @dev Updates the vesting duration for a specific VotingEscrow token.
     * @param tokenId The identifier of the VotingEscrow token whose vesting duration is being updated.
     * @param newDuration The new vesting duration for the token.
     */
    function updateVestingDuration(uint256 tokenId, uint256 newDuration) external;
}
