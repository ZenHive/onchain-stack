// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Test interface for codegen
/// @notice A minimal interface exercising structs, enums, NatSpec, and constants
interface ITestContract {
    struct UserData {
        uint256 balance;
        address owner;
        bool active;
    }

    struct Nested {
        uint256 id;
        UserData data;
    }

    enum Status { Pending, Active, Closed }

    event Updated(UserData data);
    error BadData(UserData data);

    /// @notice Get user data by address
    /// @param user The user address to query
    /// @return data The user's data struct
    function getUserData(address user) external view returns (UserData memory data);

    /// @notice Transfer tokens to a recipient
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success Whether the transfer succeeded
    function transfer(address to, uint256 amount) external returns (bool success);

    /// @notice Get the token decimals
    function decimals() external pure returns (uint8);

    /**
     * @notice Get the token name
     * @return name The token name string
     */
    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function getNested() external view returns (Nested memory);
}
