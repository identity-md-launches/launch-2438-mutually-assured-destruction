# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 for an IdentityMD custom token launch on Ethereum.

| Parameter        | Value                                                  |
| ---------------- | ------------------------------------------------------ |
| Contract         | `MADToken` (`src/MADToken.sol`)                        |
| Name             | Mutually Assured Destruction                           |
| Symbol           | MAD                                                    |
| Decimals         | 18                                                     |
| Total supply     | 1,000,000,000 MAD = `1000000000000000000000000000` minor units |
| Minted to        | `msg.sender` of the constructor, once                  |
| Constructor args | none                                                   |
| Owner            | none (no admin surface)                                |

## Behaviour

- **Constructor.** Sets `totalSupply` to `INITIAL_SUPPLY` (1e9 × 1e18), credits the whole amount to
  the deployer and emits `Transfer(0, deployer, INITIAL_SUPPLY)`. At launch the deployer is the
  ProjectFactory, which pays the supply out (swarm share, pool seed, requester's remainder). The
  constructor makes no external call and needs no address to have code.
- **ERC-20.** `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, `totalSupply`,
  `name`, `symbol`, `decimals`. Transfers move exactly the amount asked: no tax, no reflection, no
  burn on transfer, no exemptions needed. An allowance of `type(uint256).max` is unlimited and is
  not decremented.
- **Burn.** `burn(uint256)` destroys the caller's own tokens and lowers `totalSupply`. There is no
  `burnFrom`: nobody can burn, move or freeze another holder's balance.
- **Nothing else.** No mint after the constructor, no owner, no pause, no allow- or block-list, no
  proxy, no `delegatecall`, no `selfdestruct`, no `receive`/`fallback` (plain ether is rejected).
  The supply can only shrink.

Failure cases revert with custom errors: `InvalidReceiver` (transfer to the zero address; use
`burn` instead), `InvalidSpender` (approve the zero address), `InsufficientBalance`,
`InsufficientAllowance`.

## Assumptions

- The brief asks for name, symbol and supply only. The token is therefore a plain ERC-20 plus a
  holder-only burn, which the name invites and the launch floor allows (the supply may shrink,
  never grow). No fee, tax or reflection was requested, so none is implemented; adding one later is
  a new launch, not a setting.
- Because transfers are untaxed, the token does not need the factory, PoolManager or distributor
  addresses and takes no constructor arguments. The launch flows (factory → MerkleDistributor,
  factory → pool seed, PoolManager ↔ traders) move exactly what they say.
- `INITIAL_SUPPLY` is a compile-time constant: the manifest's `token.totalSupply` is
  `1000000000000000000000000000` and `token.decimals` is `18`.
- The `approve` race (a spender front-running a decrease) is inherent to ERC-20 `approve`; holders
  who care should set the allowance to zero before changing it.

## Deployment parameters

Decided by the launch, not by this repository, and reproduced here for reference:

| Setting              | Value                                                                   |
| -------------------- | ----------------------------------------------------------------------- |
| Chain                | Ethereum (chain id 1)                                                   |
| Launch kind          | `custom_token`, deployed through `ProjectFactory.launchCustom`          |
| Token contract       | `MADToken`, constructor args `[]`                                       |
| Application contracts | none                                                                  |
| Paired currency      | FWA, `0xa0df17b5ac76ababa36e1450e2cbcd18a620c845` (18 decimals)         |
| Pool fee             | 12500 (1.25%)                                                           |
| Tick spacing         | 60                                                                      |
| Initial price field  | `79228162514264337593543950336` (provenance only; the deployer derives the opening price) |
| Economics            | `poolBps` 8200, `initialMarketCapWei` 2000000000000000000000000 (FWA minor units), `remainderTo` `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d` |

Supply flow at launch, all paid by the factory from the constructor mint:

| Share | Destination                                                    |
| ----- | -------------------------------------------------------------- |
| 10%   | the launch's MerkleDistributor (swarm share, fixed by the launch) |
| 82%   | single-sided seed of the MAD/FWA Uniswap v4 pool                |
| 8%    | `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d` (`economics.remainderTo`) |

`launch.json` is written by the manifest step after this work is accepted; it is deliberately not
part of this repository.

## After launch

Nothing to configure. The token has no owner and no settable values, so there is no setter to call
and no key to hold. Operational responsibilities that remain:

- **Explorer verification.** The launch deployer verifies the source on Etherscan after deployment
  (`forge verify-contract` with `solc 0.8.26`, optimizer on, 200 runs, `bytecode_hash = "none"`).
- **Holders.** Burning is irreversible and holder-initiated. A transfer to the zero address is
  refused so that only an explicit `burn` destroys tokens.
- **No recovery.** Tokens sent to a wrong address, including the token contract itself, cannot be
  recovered: there is no admin and no sweep function. Communicate this to holders.

## Building and testing

Foundry only. The pinned compiler is `solc = "0.8.26"`, `evm_version = "cancun"`, optimizer on with
200 runs, `bytecode_hash = "none"` (the launch compares deployed bytes without the metadata hash).

```sh
forge build
forge test
forge fmt --check
```

Tests live in `test/MADToken.t.sol` and cover: metadata; the constructor mint and its event;
`transfer` success, zero amount, self-transfer, whole balance, insufficient balance, zero receiver;
`approve` success, overwrite, zero spender; `transferFrom` success, unlimited allowance, missing or
short allowance, short balance, zero receiver; `burn` success, whole supply, over-balance, empty
account, caller-only; the absence of any mint or admin selector; ether rejection; and fuzz tests for
supply conservation, over-balance reverts, exact allowance spending and exact burn accounting.

Tests set no environment variables and do not depend on the calling address; every actor is a
constant address pranked explicitly, so they pass in any order and in parallel.

### Dependencies

`lib/forge-std` is a vendored, minimal subset of forge-std (`Vm` with the cheatcodes these tests
use, and a `Test` base with revert-based assertions and `bound`). It is committed as plain files,
not a submodule, so the project builds offline. No other dependency: the token is self-contained
and vendors no OpenZeppelin code.

## Security notes

Walked against the eth-security checklist:

- **Access control.** No privileged function exists; the only state changes are a holder's own
  transfer, approve and burn.
- **Reentrancy.** No external calls anywhere, so no reentrancy surface.
- **Integer math.** Arithmetic is checked except where a prior check makes it safe (a balance
  decrement after a `balance < amount` check; a credit bounded by the fixed supply).
- **Input validation.** Zero receiver and zero spender revert; zero amounts are accepted as the
  ERC-20 standard requires.
- **Events.** Every balance or allowance change emits `Transfer` or `Approval`.
- **Supply.** No mint path; the protected floor's `mint`, `issue`, `setMinter`, `upgradeTo`,
  `initialize` and `unpause` probes all revert with no matching selector.
- **Bytecode.** No `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`; no library linking (no libraries).

Passing tests are not an audit. Static analysis (Slither, Mythril) was not run in this environment;
an independent review before release is the launch policy's, not this task's.
