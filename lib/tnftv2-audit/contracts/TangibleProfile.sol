// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "./interfaces/ITangibleProfile.sol";

/**
 * @title TangibleNFTDeployer
 * @author Veljko Mihailovic
 * @notice This contract is used to track and manage user profiles from the front end.
 */
contract TangibleProfile is ITangibleProfile {
    // ~ State Variables

    /// @notice This mapping is used to map EOA address to profile object.
    mapping(address => Profile) public userProfiles;

    // ~ Modifiers ~

    /**
     * @notice This method is used to update profile objects.
     * @dev The profile we're updating is the msg.sender.
     * @param profile The new profile object.
     */
    function update(Profile memory profile) external override {
        address owner = msg.sender;
        emit ProfileUpdated(userProfiles[owner], profile);
        userProfiles[owner] = profile;
    }

    /**
     * @notice This method is used to delete profiles.
     * @dev The profile we're updating is the msg.sender.
     */
    function remove() external override {
        address owner = msg.sender;
        emit ProfileDeleted(userProfiles[owner]);
        delete userProfiles[owner];
    }

    /**
     * @notice This method is used to fetch a list of usernames of profiles, given the addresses.
     * @param owners Array of addresses we wish to query usernames from.
     * @return names -> An array of usernames (type string).
     */
    function namesOf(
        address[] calldata owners
    ) external view override returns (string[] memory names) {
        uint256 length = owners.length;
        names = new string[](length);

        for (uint256 i; i < length; ) {
            names[i] = userProfiles[owners[i]].userName;

            unchecked {
                ++i;
            }
        }

        return names;
    }
}
