// SPDX-License-Identifier: MIT AND Apache-2.0

pragma solidity ^0.8.13;

/// @title CounterForTest
/// @notice A simple counter contract used for testing purposes
/// @dev Basic counter functionality with increment and read operations
contract CounterForTest {
    /// @notice The current count value
    uint256 public count;

    /// @notice Increments the counter by 1
    /// @dev External function that increases count by 1
    function increment() external {
        count += 1;
    }

    /// @notice Gets the current counter value
    /// @dev External view function to read the current count
    /// @return The current value of count
    function getCount() external view returns (uint256) {
        return count;
    }
}
