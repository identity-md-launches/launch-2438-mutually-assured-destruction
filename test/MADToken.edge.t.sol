// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Deploys MAD from a contract, the way ProjectFactory does, and pays the supply out in the
/// same call: the swarm's 10% to the distributor, 82% to the pool, the rest to the requester.
contract FactoryProbe {
    MADToken public token;

    function deploy(bytes32 salt) external returns (MADToken deployed) {
        deployed = new MADToken{salt: salt}();
        token = deployed;
    }

    function payOut(address distributor, address pool, address requester)
        external
        returns (uint256 swarm, uint256 seed, uint256 remainder)
    {
        uint256 supply = token.totalSupply();
        swarm = supply * 1_000 / 10_000;
        seed = supply * 8_200 / 10_000;
        remainder = token.balanceOf(address(this)) - swarm - seed;
        require(token.transfer(distributor, swarm), "swarm");
        require(token.transfer(pool, seed), "seed");
        require(token.transfer(requester, remainder), "remainder");
    }
}

/// @notice Edge cases the main suite does not pin: zero and maximum amounts, allowance boundaries,
/// the order failure checks run in, a contract deployer, and the launch's payout arriving whole.
contract MADTokenEdgeTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    MADToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new MADToken();
    }

    // ------------------------------------------------------------------ launch shape

    function test_supplyIsExactlyTheManifestValue() public view {
        assertEq(token.totalSupply(), 1000000000000000000000000000, "minor units");
        assertEq(token.INITIAL_SUPPLY(), token.totalSupply(), "constant equals live supply at deployment");
    }

    function test_contractDeployerReceivesSupplyAndPaysOutWhole() public {
        FactoryProbe factory = new FactoryProbe();
        MADToken launched = factory.deploy(bytes32(uint256(1)));
        assertEq(launched.balanceOf(address(factory)), SUPPLY, "factory holds the supply");
        assertEq(launched.balanceOf(address(this)), 0, "the caller of the factory got nothing");

        address distributor = address(0xD157);
        address pool = address(0x9001);
        address requester = address(0x1ee3);
        (uint256 swarm, uint256 seed, uint256 remainder) = factory.payOut(distributor, pool, requester);
        assertEq(swarm, SUPPLY / 10, "10% swarm");
        assertEq(seed, SUPPLY * 82 / 100, "82% pool seed");
        assertEq(remainder, SUPPLY * 8 / 100, "8% remainder");
        assertEq(launched.balanceOf(distributor), swarm, "swarm share arrived whole");
        assertEq(launched.balanceOf(pool), seed, "seed arrived whole");
        assertEq(launched.balanceOf(requester), remainder, "remainder arrived whole");
        assertEq(launched.balanceOf(address(factory)), 0, "factory keeps nothing");
        assertEq(launched.totalSupply(), SUPPLY, "payout did not change the supply");

        // The distributor's claims arrive whole too.
        vm.prank(distributor);
        launched.transfer(CAROL, swarm);
        assertEq(launched.balanceOf(CAROL), swarm, "a claim arrived whole");
    }

    function test_create2DeploymentsAreIndependent() public {
        FactoryProbe factory = new FactoryProbe();
        MADToken first = factory.deploy(bytes32(uint256(1)));
        MADToken second = factory.deploy(bytes32(uint256(2)));
        assertTrue(address(first) != address(second), "distinct addresses");
        assertEq(first.balanceOf(address(factory)), SUPPLY, "first minted once");
        assertEq(second.balanceOf(address(factory)), SUPPLY, "second minted once");
    }

    function test_sameSaltCannotRedeploy() public {
        FactoryProbe factory = new FactoryProbe();
        factory.deploy(bytes32(uint256(7)));
        vm.expectRevert();
        factory.deploy(bytes32(uint256(7)));
    }

    // ------------------------------------------------------------------ zero amounts

    function test_burnZeroIsANoOpThatEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(BOB, address(0), 0);
        vm.prank(BOB);
        token.burn(0);
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferFromZeroWithoutAllowanceSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 0), "zero spend needs no allowance");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "nothing moved");
        assertEq(token.allowance(DEPLOYER, ALICE), 0, "no allowance created");
    }

    function test_transferFromZeroStillRejectsZeroReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, address(0), 0);
    }

    function test_transferZeroToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 0);
    }

    function test_approveZeroClearsAllowance() public {
        vm.startPrank(DEPLOYER);
        token.approve(ALICE, 500);
        token.approve(ALICE, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    // ------------------------------------------------------------------ allowance boundaries

    function test_allowanceOneBelowMaxIsDecremented() public {
        uint256 allowed = type(uint256).max - 1;
        vm.prank(DEPLOYER);
        token.approve(ALICE, allowed);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
        assertEq(token.allowance(DEPLOYER, ALICE), allowed - 1, "only the exact max is unlimited");
    }

    function test_unlimitedAllowanceStillBoundedByBalance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, DEPLOYER, SUPPLY, SUPPLY + 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, SUPPLY + 1);
    }

    function test_exactAllowanceIsFullySpent() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 77);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 77);
        assertEq(token.allowance(DEPLOYER, ALICE), 0, "allowance exhausted");
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    function test_selfSpendStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 1);
    }

    function test_selfSpendWithSelfAllowance() public {
        vm.startPrank(DEPLOYER);
        token.approve(DEPLOYER, 10);
        token.transferFrom(DEPLOYER, ALICE, 10);
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), 10, "moved");
        assertEq(token.allowance(DEPLOYER, DEPLOYER), 0, "self-allowance spent");
    }

    function test_transferFromDoesNotEmitApproval() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 100);
        // The only event of a spend is the Transfer; the allowance change is read, not logged.
        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, BOB, 40);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 40);
        assertEq(token.allowance(DEPLOYER, ALICE), 60, "allowance reduced");
    }

    function test_allowanceIsPerOwner() public {
        vm.prank(DEPLOYER);
        token.transfer(CAROL, 100);
        vm.prank(DEPLOYER);
        token.approve(ALICE, 100);
        // Alice's allowance from the deployer gives her nothing over Carol's tokens.
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(CAROL, BOB, 1);
    }

    // ------------------------------------------------------------------ failure ordering

    /// @dev Allowance is checked before balance: an unapproved spender learns nothing about balances.
    function test_allowanceCheckedBeforeBalance() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, ALICE, 0, 5));
        vm.prank(ALICE);
        token.transferFrom(BOB, CAROL, 5);
    }

    function test_failedTransferFromLeavesAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 50);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, ALICE, 10, 20));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 20);
        assertEq(token.allowance(ALICE, BOB), 50, "the revert rolled the allowance spend back");
    }

    function test_burnMaxUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(MADToken.InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(DEPLOYER);
        token.burn(type(uint256).max);
    }

    function test_transferMaxUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(MADToken.InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, type(uint256).max);
    }

    function test_burnAfterTransferAwayReverts() public {
        vm.startPrank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, DEPLOYER, 0, 1));
        token.burn(1);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ irreversibility

    function test_tokensSentToTheTokenAreStuck() public {
        vm.prank(DEPLOYER);
        token.transfer(address(token), 1_000);
        assertEq(token.balanceOf(address(token)), 1_000, "the token can receive itself");
        assertEq(token.totalSupply(), SUPPLY, "they still count toward the supply");
        // Nobody can spend them: the token never approves or transfers on its own behalf.
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(address(token), DEPLOYER, 1);
    }

    function test_supplyCannotBeRestoredAfterBurn() public {
        vm.prank(DEPLOYER);
        token.burn(SUPPLY);
        assertEq(token.totalSupply(), 0, "all burned");
        // A burnt-out token is still a working token for zero-value calls, and still refuses the rest.
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 0), "zero transfer still works");
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1);
    }

    function test_unknownCalldataReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("initialize()"));
        assertFalse(ok, "initialize");
        (ok,) = address(token).call(abi.encodeWithSignature("unpause()"));
        assertFalse(ok, "unpause");
        (ok,) = address(token).call(abi.encodeWithSignature("issue(uint256)", uint256(1)));
        assertFalse(ok, "issue");
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "arbitrary selector");
        assertEq(token.totalSupply(), SUPPLY, "supply untouched");
    }

    // ------------------------------------------------------------------ fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromRevertsAboveAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        amount = bound(amount, allowed + 1, type(uint256).max);
        vm.prank(DEPLOYER);
        token.approve(ALICE, allowed);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, ALICE, allowed, amount));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, amount);
        assertEq(token.allowance(DEPLOYER, ALICE), allowed, "allowance untouched");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "balance untouched");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_burnRevertsAboveBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.burn(amount);
        assertEq(token.totalSupply(), SUPPLY, "supply untouched");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveIsExactAndOverwrites(uint256 first, uint256 second) public {
        vm.startPrank(ALICE);
        token.approve(BOB, first);
        assertEq(token.allowance(ALICE, BOB), first, "first");
        vm.expectEmit(true, true, true, true);
        emit Approval(ALICE, BOB, second);
        token.approve(BOB, second);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), second, "second replaces first");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_chainedTransfersConserve(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, a);
        b = bound(b, 0, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        c = bound(c, 0, b);
        vm.prank(BOB);
        token.burn(c);
        uint256 sum = token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB);
        assertEq(sum, token.totalSupply(), "balances sum to supply");
        assertEq(token.totalSupply(), SUPPLY - c, "only the burn changed the supply");
        assertEq(token.balanceOf(BOB), b - c, "bob");
        assertEq(token.balanceOf(ALICE), a - b, "alice");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_burnFullBalanceOfAnyHolder(address holder, uint256 held) public {
        holder = holder == address(0) ? ALICE : holder;
        held = bound(held, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(holder, held);
        uint256 balance = token.balanceOf(holder);
        vm.prank(holder);
        token.burn(balance);
        assertEq(token.balanceOf(holder), 0, "holder emptied");
        assertEq(token.totalSupply(), SUPPLY - balance, "supply dropped by exactly the balance");
    }
}
