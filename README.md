## RealETH

RealETH: The Ultimate native yield bearing token powering the re.al Chain!

#### Vault

The RealETH Vault is responsible for managing deposit, withdrawal, and settlement processes using ERC4626 standard. Serving as the fund buffering pool, it holds deposited ETH within the contract until a new settlement occurs, at which point the funds are deployed to the underlying strategy pool.

#### Minter

The Minter handles the minting and burning of RealETH tokens. This function decouples RealETH token minting from its underlying assets, allowing for independent adjustments to the assets and the circulation of issued RealETH tokens. This separation ensures a higher level of token stability within the Real Network ecosystem.

#### Strategy Pool

The Strategy Pool manages asset yield routes through a whitelist mechanism. This approach ensures a high level of asset compatibility, including staking pools, restaking protocols, and more. Each individual strategy route within the pool isolates asset risks, preventing cross-contamination and maintaining the security of RealETH assets.

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
