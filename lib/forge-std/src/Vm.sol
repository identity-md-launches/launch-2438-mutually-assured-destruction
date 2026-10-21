// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @notice The subset of Foundry cheatcodes this project's tests use. The cheatcode contract lives
/// at `address(uint160(uint256(keccak256("hevm cheat code"))))` and is dispatched by selector, so
/// only the signatures matter. Each one is declared exactly as in forge-std's `Vm`.
interface Vm {
    /// @dev Sets `msg.sender` for the next call only.
    function prank(address msgSender) external;

    /// @dev Sets `msg.sender` for every call until `stopPrank`.
    function startPrank(address msgSender) external;

    /// @dev Ends a `startPrank`.
    function stopPrank() external;

    /// @dev Expects the next call to revert with any data.
    function expectRevert() external;

    /// @dev Expects the next call to revert with exactly this selector.
    function expectRevert(bytes4 revertData) external;

    /// @dev Expects the next call to revert with exactly this data.
    function expectRevert(bytes calldata revertData) external;

    /// @dev Expects the next call to emit an event matching the one emitted right after this call.
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;

    /// @dev Discards a fuzz input when `condition` is false.
    function assume(bool condition) external pure;

    /// @dev Gives an address a label in traces.
    function label(address account, string calldata newLabel) external;

    /// @dev Sets an account's ether balance.
    function deal(address account, uint256 newBalance) external;
}
