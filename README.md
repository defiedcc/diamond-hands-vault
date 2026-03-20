# Diamond Hands Vault

A smart contract vault that locks ETH deposits until ETH/USD reaches a specified all-time high price target. While locked, deposited ETH earns staking rewards through [Lido](https://lido.fi/).

## How It Works

1. **Deposit** — Users send ETH to the vault (via `deposit()` or directly). The vault stakes it via Lido (`stETH`) and wraps it into `wstETH` to compound rewards automatically.
2. **Hold** — Deposits remain locked until the ETH price reaches the configured all-time high target (verified via Chainlink oracle).
3. **Withdraw** — Once the target is reached, users withdraw their full `wstETH` balance with no fees. Early exits before the target incur a configurable fee (in basis points).

## Key Features

- **Lido staking integration** — deposited ETH earns staking yield as wstETH
- **Chainlink price oracle** — ETH/USD price verified on-chain with staleness checks (max 1 hour)
- **Early exit fee** — configurable penalty (basis points) for withdrawals before the price target is met
- **Permissionless ATH trigger** — anyone can call `notifyAllTimeHigh()` to unlock fee-free withdrawals once the price target is reached
- **One-way state transition** — once the all-time high is reached, deposits are disabled and all withdrawals become fee-free
- **Ethereum Mainnet only** — enforced at deployment via `block.chainid` check; external addresses (wstETH, stETH, Chainlink feed) are passed as immutable constructor parameters
- **Constructor validations** — zero-address checks on all address parameters, max early exit fee capped at 10% (1000 bps), non-zero price target required
- **Safe token transfers** — uses OpenZeppelin's `SafeERC20` for all ERC20 interactions

## Build & Test

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
# Build
forge build

# Run tests
forge test -vvv

# Format
forge fmt
```

## Deployment

Constructor parameters:

| Parameter | Description |
|---|---|
| `_allTimeHigh` | Target ETH/USD price (8 decimals, Chainlink format) |
| `_earlyExitFeeBps` | Early exit fee in basis points (e.g., 500 = 5%) |
| `_exitFeeRecipient` | Address that receives early exit fees |
| `_wstETH` | Lido wrapped stETH contract address |
| `_stETH` | Lido stETH contract address |
| `_priceFeed` | Chainlink ETH/USD price feed address |

### Reference Addresses (Ethereum Mainnet)

| Dependency | Address |
|---|---|
| wstETH | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` |
| stETH | `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84` |
| Chainlink ETH/USD | `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419` |

## License

MIT
