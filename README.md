# moonbeam-staking-pool-stakebaby

A staking pool based on an ERC20 liquid token and multiple ledgers. The contracts secure customer funds and expose methods for off-chain delegations management.


## Contracts
The pool is implemented as a set of smart contracts.
These contracts are located in the [contracts/](contracts/) directory.

### [StakingPool](contracts/StakingPool.sol)
Staking pool business logic. The pool manages/accesses all other contracts and accepts the funds from delegators.
https://moonbeam.moonscan.io/address/0xE48Df88bD2855ab27FA29d433E0DE6BeD0F2C1a8

### [Ledger](contracts/Ledger.sol)
Acts as a solo smart contract delegator for delegating funds to collators. Multiple ledgers are required to efficiently manage the delegation portfolio.
Ledgers are created and destroyed by the pool contract. You can query ledger addresses by querying the public ledgers array of the StakingPool contract.

### [TokenLiquidStaking](contracts/TokenLiquidStaking.sol)
The Liquid Staking token that is issued in exchange for underlying (GLMR or MOVR).
https://moonbeam.moonscan.io/token/0x2e506923a408e308E75ef4BE574681197f2a6460

### [Claimable](contracts/Claimable.sol)
A contract dedicated to withdrawals of scheduled+executed undelegations.
https://moonbeam.moonscan.io/address/0x9bf0F6222fFdD01C36339df8E757EF105C9447Fe

## Quick start
### Install dependencies

```bash=
npm i
truffle run moonbeam install
truffle run moonbeam start
# make sure Moonbeam node is v0.27.2 or later; if not, remove old docker image and reinstall
```

### Compile contracts

```bash
truffle compile
```

### Run tests

```bash
truffle test --network dev
```

### Migrate

```bash
truffle migrate --network dev
```
