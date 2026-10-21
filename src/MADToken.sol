// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Mutually Assured Destruction (MAD)
/// @notice A fixed-supply ERC-20. The whole supply, 1,000,000,000 MAD with 18 decimals, is minted
/// once to the deployer in the constructor. Nothing can mint afterwards; any holder may burn their
/// own tokens, so the supply can only ever shrink.
/// @dev Self-contained: no owner, no pause, no allow- or block-list, no hooks, no proxies, no
/// external calls. Transfers move exactly the amount asked, so the launch flows (factory to
/// distributor, factory into the pool, pool to and from traders) arrive whole. The Solidity name
/// `MADToken` is the launch's contract name; `name()` and `symbol()` carry the token's.
contract MADToken {
    // ------------------------------------------------------------------ metadata

    /// @notice ERC-20 name.
    string public constant name = "Mutually Assured Destruction";

    /// @notice ERC-20 symbol.
    string public constant symbol = "MAD";

    /// @notice ERC-20 decimals.
    uint8 public constant decimals = 18;

    /// @notice The supply minted once at deployment: 1,000,000,000 MAD in minor units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    // ------------------------------------------------------------------ storage

    /// @notice Tokens in existence. Starts at `INITIAL_SUPPLY` and only decreases through `burn`.
    uint256 public totalSupply;

    /// @notice Balance of each holder.
    mapping(address account => uint256) public balanceOf;

    /// @notice Remaining amount `spender` may move from `owner` through `transferFrom`.
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    // ------------------------------------------------------------------ events

    /// @notice Emitted on every transfer, mint (from the zero address) and burn (to the zero address).
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when an allowance is set.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ------------------------------------------------------------------ errors

    /// @notice Tokens may not be transferred to the zero address; use `burn` to destroy them.
    error InvalidReceiver(address receiver);

    /// @notice The zero address may not be approved as a spender.
    error InvalidSpender(address spender);

    /// @notice `sender` holds `balance` but `needed` was required.
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @notice `spender` may move `allowance_` but `needed` was required.
    error InsufficientAllowance(address spender, uint256 allowance_, uint256 needed);

    // ------------------------------------------------------------------ constructor

    /// @notice Mints the whole supply to the deployer. At launch the deployer is the factory, which
    /// pays the supply out: the swarm's share, the pool seed and the requester's remainder.
    constructor() {
        totalSupply = INITIAL_SUPPLY;
        balanceOf[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    // ------------------------------------------------------------------ ERC-20

    /// @notice Moves `amount` from the caller to `to`.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Lets `spender` move up to `amount` of the caller's tokens.
    /// @dev Sets the allowance outright; a spender front-running a decrease can spend the old and
    /// the new value, as with every ERC-20 `approve`. Set the allowance to zero first when that
    /// matters.
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Moves `amount` from `from` to `to` using the caller's allowance.
    /// @dev An allowance of `type(uint256).max` is treated as unlimited and is not reduced.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // ------------------------------------------------------------------ burn

    /// @notice Destroys `amount` of the caller's own tokens. Only the holder can burn, and only
    /// what they hold. This is the one way the supply changes after deployment.
    function burn(uint256 amount) external {
        uint256 balance = balanceOf[msg.sender];
        if (balance < amount) revert InsufficientBalance(msg.sender, balance, amount);
        unchecked {
            balanceOf[msg.sender] = balance - amount;
            // The burned amount is bounded by a balance, and every balance is bounded by the supply.
            totalSupply -= amount;
        }
        emit Transfer(msg.sender, address(0), amount);
    }

    // ------------------------------------------------------------------ internals

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert InvalidReceiver(address(0));
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance(from, balance, amount);
        unchecked {
            balanceOf[from] = balance - amount;
            // The sum of all balances is the supply, which fits in uint256, so no balance overflows.
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (spender == address(0)) revert InvalidSpender(address(0));
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 current = allowance[owner][spender];
        if (current == type(uint256).max) return;
        if (current < amount) revert InsufficientAllowance(spender, current, amount);
        unchecked {
            allowance[owner][spender] = current - amount;
        }
    }
}
