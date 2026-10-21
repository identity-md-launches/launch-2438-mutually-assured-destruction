// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Behaviour of the MAD token: the constructor mint, every ERC-20 path's success and
/// failure cases, the holder-only burn, and the absence of any mint or admin surface.
contract MADTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Stands in for the factory: the address that deploys and so receives the whole supply.
    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    MADToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new MADToken();
        vm.label(address(token), "MAD");
    }

    // ------------------------------------------------------------------ metadata

    function test_metadata() public view {
        assertEq(token.name(), "Mutually Assured Destruction", "name");
        assertEq(token.symbol(), "MAD", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    // ------------------------------------------------------------------ constructor

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "INITIAL_SUPPLY constant");
        assertEq(token.totalSupply(), SUPPLY, "totalSupply");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "deployer balance");
        assertEq(token.balanceOf(address(this)), 0, "the test harness holds nothing");
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        MADToken fresh = new MADToken();
        assertEq(fresh.balanceOf(ALICE), SUPPLY, "whoever deploys receives the supply");
    }

    // ------------------------------------------------------------------ transfer

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_000 * 10 ** 18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, ALICE, amount);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount), "transfer returns true");
        assertEq(token.balanceOf(ALICE), amount, "receiver balance");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender balance");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY, "receiver got everything");
        assertEq(token.balanceOf(DEPLOYER), 0, "sender is empty");
    }

    function test_transferZeroAmount() public {
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, 0), "a zero transfer succeeds even from an empty account");
        assertEq(token.balanceOf(ALICE), 0, "nothing moved");
    }

    function test_transferToSelf() public {
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, 5);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "self-transfer leaves the balance unchanged");
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(ALICE);
        token.transfer(BOB, 11);
        assertEq(token.balanceOf(ALICE), 10, "nothing left Alice");
        assertEq(token.balanceOf(BOB), 0, "nothing reached Bob");
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY, "a transfer to zero is not a burn");
    }

    // ------------------------------------------------------------------ approve

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(ALICE, BOB, 123);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 123), "approve returns true");
        assertEq(token.allowance(ALICE, BOB), 123, "allowance set");
        assertEq(token.allowance(BOB, ALICE), 0, "allowance is directional");
    }

    function test_approveOverwrites() public {
        vm.startPrank(ALICE);
        token.approve(BOB, 100);
        token.approve(BOB, 7);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), 7, "approve replaces rather than adds");
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 1);
    }

    // ------------------------------------------------------------------ transferFrom

    function test_transferFromSpendsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 100);
        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, BOB, 60);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 60), "transferFrom returns true");
        assertEq(token.balanceOf(BOB), 60, "receiver balance");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 60, "owner balance");
        assertEq(token.balanceOf(ALICE), 0, "the spender holds nothing");
        assertEq(token.allowance(DEPLOYER, ALICE), 40, "allowance reduced by the amount moved");
    }

    function test_transferFromUnlimitedAllowanceIsNotReduced() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1_000);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max, "unlimited stays unlimited");
        assertEq(token.balanceOf(BOB), 1_000, "tokens moved");
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "nothing moved");
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 50);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, ALICE, 50, 51));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 51);
        assertEq(token.allowance(DEPLOYER, ALICE), 50, "allowance untouched by the failed call");
    }

    function test_transferFromRevertsBeyondBalanceEvenWithAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 1_000);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 11);
    }

    function test_transferFromRevertsToZeroAddress() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, address(0), 1);
    }

    // ------------------------------------------------------------------ burn

    function test_burnReducesBalanceAndSupply() public {
        uint256 amount = 250 * 10 ** 18;
        vm.prank(DEPLOYER);
        token.transfer(ALICE, amount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, address(0), 100 * 10 ** 18);
        vm.prank(ALICE);
        token.burn(100 * 10 ** 18);
        assertEq(token.balanceOf(ALICE), 150 * 10 ** 18, "burner balance");
        assertEq(token.totalSupply(), SUPPLY - 100 * 10 ** 18, "supply shrank by the burn");
        assertEq(token.balanceOf(address(0)), 0, "nothing accumulates at the zero address");
    }

    function test_burnWholeSupply() public {
        vm.prank(DEPLOYER);
        token.burn(SUPPLY);
        assertEq(token.totalSupply(), 0, "everything destroyed");
        assertEq(token.balanceOf(DEPLOYER), 0, "deployer empty");
    }

    function test_burnRevertsBeyondBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 5);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, ALICE, 5, 6));
        vm.prank(ALICE);
        token.burn(6);
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged by the failed burn");
    }

    function test_burnRevertsForEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.burn(1);
    }

    function test_burnOnlyTouchesTheCaller() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        // Bob has an unlimited allowance from Alice, but burn has no "from": it only burns the caller's.
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.burn(1);
        assertEq(token.balanceOf(ALICE), 100, "Alice keeps her tokens");
    }

    // ------------------------------------------------------------------ no mint, no admin

    function test_noMintOrAdminSurface() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "setOwner(address)",
            "transferOwnership(address)",
            "owner()",
            "setMinter(address)",
            "upgradeTo(address)"
        ];
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1));
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(BOB);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
        assertEq(token.balanceOf(ALICE), 1_000, "holder balance unchanged");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 500), "holder can still transfer");
    }

    function test_plainEtherIsRejected() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "the token has no receive or fallback");
        assertEq(address(token).balance, 0, "no ether held");
    }

    // ------------------------------------------------------------------ fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(to, amount);
        if (to == DEPLOYER) {
            assertEq(token.balanceOf(DEPLOYER), SUPPLY, "self-transfer conserves");
        } else {
            assertEq(token.balanceOf(to), amount, "receiver got the amount");
            assertEq(token.balanceOf(DEPLOYER) + token.balanceOf(to), SUPPLY, "balances sum to the supply");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply is unchanged by transfers");
    }

    function testFuzz_transferRevertsAboveBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
    }

    function testFuzz_transferFromSpendsExactly(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, 0, allowed);
        vm.prank(DEPLOYER);
        token.approve(ALICE, allowed);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, amount);
        assertEq(token.allowance(DEPLOYER, ALICE), allowed - amount, "allowance reduced exactly");
        assertEq(token.balanceOf(BOB), amount, "receiver balance");
    }

    function testFuzz_burnShrinksSupplyExactly(uint256 held, uint256 burned) public {
        held = bound(held, 0, SUPPLY);
        burned = bound(burned, 0, held);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.burn(burned);
        assertEq(token.balanceOf(ALICE), held - burned, "burner balance");
        assertEq(token.totalSupply(), SUPPLY - burned, "supply");
        assertEq(token.balanceOf(DEPLOYER) + token.balanceOf(ALICE), token.totalSupply(), "balances sum to supply");
    }
}
