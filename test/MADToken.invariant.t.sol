// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Drives MAD with random, bounded calls from a fixed set of actors and keeps ghost
/// accounting of what the token should hold. Failure paths are driven too: each one must revert
/// with the expected error and leave every balance, allowance and the supply untouched.
contract MADHandler {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MADToken public immutable token;
    uint256 public immutable initialSupply;

    address[] public actors;

    // Ghost state: what the token should report.
    uint256 public ghostBurned;
    uint256 public ghostMinted;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    // Ghost observations across the run.
    uint256 public lowestSupplySeen;
    bool public supplyEverIncreased;
    bool public unexpectedOutcome;
    string public unexpectedReason;

    // Call counters, so a run that exercised nothing is visible.
    uint256 public calls;
    uint256 public expectedReverts;

    constructor(address[] memory actors_) {
        // The handler deploys the token, so it is the deployer and receives the whole supply,
        // which it then hands to the first actor: the stand-in for the factory paying out.
        token = new MADToken();
        initialSupply = token.totalSupply();
        ghostMinted = initialSupply;
        lowestSupplySeen = initialSupply;
        actors = actors_;
        token.transfer(actors_[0], initialSupply);
        ghostBalance[actors_[0]] = initialSupply;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ------------------------------------------------------------------ helpers

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (x >= min && x <= max) return x;
        uint256 size = max - min + 1;
        return min + (x % size);
    }

    function _flag(string memory reason) internal {
        if (!unexpectedOutcome) {
            unexpectedOutcome = true;
            unexpectedReason = reason;
        }
    }

    function _afterCall() internal {
        ++calls;
        uint256 supply = token.totalSupply();
        if (supply > lowestSupplySeen) supplyEverIncreased = true;
        if (supply < lowestSupplySeen) lowestSupplySeen = supply;
    }

    // ------------------------------------------------------------------ happy paths

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = _bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        bool ok = token.transfer(to, amount);
        if (!ok) _flag("transfer returned false");
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        _afterCall();
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        if (!ok) _flag("approve returned false");
        ghostAllowance[owner][spender] = amount;
        _afterCall();
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = _bound(amount, 0, cap);
        vm.prank(spender);
        bool ok = token.transferFrom(from, to, amount);
        if (!ok) _flag("transferFrom returned false");
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        _afterCall();
    }

    function burn(uint256 holderSeed, uint256 amount) external {
        address holder = _actor(holderSeed);
        amount = _bound(amount, 0, ghostBalance[holder]);
        vm.prank(holder);
        token.burn(amount);
        ghostBalance[holder] -= amount;
        ghostBurned += amount;
        _afterCall();
    }

    // ------------------------------------------------------------------ failure paths

    /// @dev A transfer of more than the sender holds must revert and change nothing.
    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = held + _bound(excess, 1, type(uint256).max - held);
        vm.prank(from);
        try token.transfer(to, amount) {
            _flag("transfer above balance succeeded");
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, from, held, amount))
            ) {
                _flag("transfer above balance: wrong error");
            }
            ++expectedReverts;
        }
        _afterCall();
    }

    /// @dev A transfer to the zero address must revert; it is not a burn.
    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = _bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            _flag("transfer to zero succeeded");
        } catch (bytes memory reason) {
            if (keccak256(reason) != keccak256(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)))) {
                _flag("transfer to zero: wrong error");
            }
            ++expectedReverts;
        }
        _afterCall();
    }

    /// @dev Spending more than the allowance must revert, even when the owner holds enough.
    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = allowed + _bound(excess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            _flag("transferFrom above allowance succeeded");
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, spender, allowed, amount)
                    )
            ) {
                _flag("transferFrom above allowance: wrong error");
            }
            ++expectedReverts;
        }
        _afterCall();
    }

    /// @dev Burning more than the caller holds must revert, whatever allowances the caller has.
    function burnTooMuch(uint256 holderSeed, uint256 excess) external {
        address holder = _actor(holderSeed);
        uint256 held = ghostBalance[holder];
        uint256 amount = held + _bound(excess, 1, type(uint256).max - held);
        vm.prank(holder);
        try token.burn(amount) {
            _flag("burn above balance succeeded");
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, holder, held, amount))
            ) {
                _flag("burn above balance: wrong error");
            }
            ++expectedReverts;
        }
        _afterCall();
    }

    /// @dev Approving the zero address must revert.
    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), amount) {
            _flag("approve of zero spender succeeded");
        } catch (bytes memory reason) {
            if (keccak256(reason) != keccak256(abi.encodeWithSelector(MADToken.InvalidSpender.selector, address(0)))) {
                _flag("approve of zero spender: wrong error");
            }
            ++expectedReverts;
        }
        _afterCall();
    }
}

/// @notice Invariants of MAD over random call sequences: the supply is fixed except for burns and
/// never grows, every unit is held by someone the run knows about, balances and allowances are
/// exactly what the calls made, and no failure path changes anything.
contract MADTokenInvariantTest is Test {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MADHandler internal handler;
    MADToken internal token;
    address[] internal actors;

    function setUp() public {
        actors.push(address(0xFAC7));
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xD157));
        handler = new MADHandler(actors);
        token = handler.token();
    }

    /// @dev Only the handler is called; the token is reached through it so the ghosts stay exact.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = MADHandler.transfer.selector;
        selectors[1] = MADHandler.approve.selector;
        selectors[2] = MADHandler.transferFrom.selector;
        selectors[3] = MADHandler.burn.selector;
        selectors[4] = MADHandler.transferTooMuch.selector;
        selectors[5] = MADHandler.transferToZero.selector;
        selectors[6] = MADHandler.transferFromOverAllowance.selector;
        selectors[7] = MADHandler.burnTooMuch.selector;
        selectors[8] = MADHandler.approveZeroSpender.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyIsInitialMinusBurned() public view {
        assertEq(token.totalSupply(), SUPPLY - handler.ghostBurned(), "supply = minted - burned");
        assertEq(handler.ghostMinted(), SUPPLY, "nothing minted after the constructor");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyNeverGrows() public view {
        assertFalse(handler.supplyEverIncreased(), "the supply increased during the run");
        assertLe(token.totalSupply(), SUPPLY, "supply above the constructor mint");
        assertEq(token.totalSupply(), handler.lowestSupplySeen(), "supply only moves down");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply(), "every unit is held by a known actor");
        assertEq(token.balanceOf(address(handler)), 0, "the deployer kept nothing back");
        assertEq(token.balanceOf(address(token)), 0, "nothing stuck in the token");
        assertEq(token.balanceOf(address(0)), 0, "nothing at the zero address");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchGhosts() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance drifted from its ghost");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchGhosts() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance drifted from its ghost"
                );
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_failurePathsBehave() public view {
        assertFalse(handler.unexpectedOutcome(), handler.unexpectedReason());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_metadataIsConstant() public view {
        assertEq(token.name(), "Mutually Assured Destruction", "name");
        assertEq(token.symbol(), "MAD", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "INITIAL_SUPPLY");
    }
}
