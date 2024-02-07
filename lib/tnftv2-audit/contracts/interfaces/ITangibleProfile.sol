// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface ITangibleProfile {
    /**
     * @notice This struct is used to define a Profile object.
     * @param userName unique identifier for account.
     * @param imageURL url for profile image.
     */
    struct Profile {
        string userName;
        string imageURL;
    }

    /// @notice This event is emitted when a profile is updated.
    event ProfileUpdated(Profile oldProfile, Profile newProfile);

    /// @notice This event is emitted when a profile is removed.
    event ProfileDeleted(Profile removedProfile);

    /// @dev The function updates the user profile.
    function update(Profile memory profile) external;

    /// @dev The function removes the user profile.
    function remove() external;

    /// @dev The function returns name(s) of user(s).
    function namesOf(address[] calldata owners) external view returns (string[] memory);
}
