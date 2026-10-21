// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Vm} from "./Vm.sol";

/// @notice A minimal test base in the shape of forge-std's `Test`: the `vm` handle, the markers
/// forge looks for on a test contract, and assertions that revert with a readable reason. A
/// reverting test is a failing test, so no soft-failure bookkeeping is needed.
abstract contract Test {
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    bool public IS_TEST = true;
    bool private _failed;

    function failed() public view returns (bool) {
        return _failed;
    }

    // ---------------------------------------------------------------- bool

    function assertTrue(bool condition) internal pure {
        if (!condition) revert("assertion failed: expected true");
    }

    function assertTrue(bool condition, string memory err) internal pure {
        if (!condition) revert(err);
    }

    function assertFalse(bool condition) internal pure {
        if (condition) revert("assertion failed: expected false");
    }

    function assertFalse(bool condition, string memory err) internal pure {
        if (condition) revert(err);
    }

    function assertEq(bool a, bool b) internal pure {
        if (a != b) revert("assertion failed: bool mismatch");
    }

    function assertEq(bool a, bool b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    // ---------------------------------------------------------------- uint256

    function assertEq(uint256 a, uint256 b) internal pure {
        if (a != b) revert(string.concat("assertion failed: ", _u(a), " != ", _u(b)));
    }

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        if (a != b) revert(string.concat(err, ": ", _u(a), " != ", _u(b)));
    }

    function assertGt(uint256 a, uint256 b) internal pure {
        if (a <= b) revert(string.concat("assertion failed: ", _u(a), " <= ", _u(b)));
    }

    function assertGt(uint256 a, uint256 b, string memory err) internal pure {
        if (a <= b) revert(string.concat(err, ": ", _u(a), " <= ", _u(b)));
    }

    function assertGe(uint256 a, uint256 b) internal pure {
        if (a < b) revert(string.concat("assertion failed: ", _u(a), " < ", _u(b)));
    }

    function assertGe(uint256 a, uint256 b, string memory err) internal pure {
        if (a < b) revert(string.concat(err, ": ", _u(a), " < ", _u(b)));
    }

    function assertLt(uint256 a, uint256 b) internal pure {
        if (a >= b) revert(string.concat("assertion failed: ", _u(a), " >= ", _u(b)));
    }

    function assertLt(uint256 a, uint256 b, string memory err) internal pure {
        if (a >= b) revert(string.concat(err, ": ", _u(a), " >= ", _u(b)));
    }

    function assertLe(uint256 a, uint256 b) internal pure {
        if (a > b) revert(string.concat("assertion failed: ", _u(a), " > ", _u(b)));
    }

    function assertLe(uint256 a, uint256 b, string memory err) internal pure {
        if (a > b) revert(string.concat(err, ": ", _u(a), " > ", _u(b)));
    }

    // ---------------------------------------------------------------- address

    function assertEq(address a, address b) internal pure {
        if (a != b) revert("assertion failed: address mismatch");
    }

    function assertEq(address a, address b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    // ---------------------------------------------------------------- string / bytes

    function assertEq(string memory a, string memory b) internal pure {
        if (keccak256(bytes(a)) != keccak256(bytes(b))) {
            revert(string.concat("assertion failed: \"", a, "\" != \"", b, "\""));
        }
    }

    function assertEq(string memory a, string memory b, string memory err) internal pure {
        if (keccak256(bytes(a)) != keccak256(bytes(b))) revert(string.concat(err, ": \"", a, "\" != \"", b, "\""));
    }

    function assertEq(bytes memory a, bytes memory b) internal pure {
        if (keccak256(a) != keccak256(b)) revert("assertion failed: bytes mismatch");
    }

    function assertEq(bytes memory a, bytes memory b, string memory err) internal pure {
        if (keccak256(a) != keccak256(b)) revert(err);
    }

    // ---------------------------------------------------------------- fuzz helpers

    /// @dev Maps any uint256 into [min, max] so a fuzz input can be constrained without discarding it.
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) revert("bound: min > max");
        if (x >= min && x <= max) return x;
        uint256 size = max - min + 1;
        // size wraps to zero only for the full range, where x already lies within [min, max].
        return min + (x % size);
    }

    // ---------------------------------------------------------------- formatting

    function _u(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
