# moonbeam-staking-pool-stakebaby

A staking pool based on an ERC20 liquid token and multiple ledgers. The contracts secure customer funds and expose methods for off-chain delegations management.


## Contracts
The pool is implemented as a set of smart contracts.
These contracts are located in the [contracts/](contracts/) directory.

### [StakingPool](contracts/StakingPool.sol)
Staking pool business logic. The pool manages/accesses all other contracts and accepts the funds from delegators.

### [Ledger](contracts/Ledger.sol)
Acts as a solo smart contract delegator for delegating funds to collators. Multiple ledgers are required to efficiently manage the delegation portfolio.

### [TokenLiquidStaking](contracts/TokenLiquidStaking.sol)
The Liquid Staking token that is issued in exchange for underlying (GLMR or MOVR).

### [Claimable](contracts/Claimable.sol)
A contract dedicated to withdrawals of scheduled+executed undelegations.


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
