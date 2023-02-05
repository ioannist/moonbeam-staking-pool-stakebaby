# moonbeam-staking-pool-dao

A DAO managed Moonbeam/Moonriver staking pool with the following characteristics:
A1) Non-rebaseable liquid staking token pool, where delegators can delegate, schedule undelegate, execute
A2) Benefits for delegators: no min delegation, collator diversification, liquidity, shorter average undelegation time
A3) The pool will be entirely managed by the DAO, made up from community collators

Delegation and revoke logic
B1) By default, incoming delegations or undelegations (net amount) will be split evenly among member collators in round robin
B2) DAO can override the above by setting the Delegation Queue and the Undelegation Queue. These two queues define which collator to delegate to/undelegate from, up to how much, and in what sequence. Any collator can be entered here (not just member collators as above)
B3) DAO can also manually undelegate and delegate (move delegation) from/to any collator. This will give the DAO tactical flexibility to protect member collators.
B4) Since moving delegations will result to missed rewards due to undelegation delay, the DAO members must be able to deposit funds into the contract to make up for the decreased APR.

DAO Membership and Deposits
C1) DAO membership will be based on non-transferable ERC20 VoteTokens
C2) All new members start with 3000 VoteTokens. New members can be voted in through the DAO.
C3) Every month, members will be able to deposit up to 50 GLMR and get up to 50 VoteTokens. This is optional, but not participating may result to reduced voting power over time.
C4) Member deposited funds stay in the treasury and can be be moved to the staking pool to refund missed rewards (B4)

## Contracts
The pool is implemented as a set of smart contracts.
These contracts are located in the [contracts/](contracts/) directory.

### [MemberTreasury](contracts/MemberTreasury.sol)
Business logic for membership management (members, non-members, collators)

### [StakingPool](contracts/StakingPool.sol)
Staking pool business logic and underlying funds holding contract.

### [DaoMembership](contracts/DaoMembership.sol)
The OpenZeppelin DAO for managing pool membership

### [DaoStaking](contracts/DaoStaking.sol)
The OpenZeppelin DAO for managing staking

### [TokenLiquidStaking](contracts/TokenLiquidStaking.sol)
The Liquid Staking token that is issued in exchange for underlying (GLMR or MOVR).

### [TokenDao](contracts/TokenDao.sol)
The vote token for DaoMembership and DaoStaking contracts.


## Quick start
### Install dependencies

```bash=
npm i
truffle run moonbeam install
truffle run moonbeam start
# make sure Moonbeam node is v0.27.2 or later; if not, remove old docker image and reinstall
```

### Make .secret.env file in root folder

```
# Dev
DAO_STAKING="0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133" #0xf24FF3a9CF04c71Dbc94D0b566f7A27B94566cac
DAO_MEMBERS="0x8075991ce870b93a8870eca0c0f91913d12f47948ca0fd25b49c6fa7cdbeee8b" #0x3Cd0A705a2DC65e5b1E1205896BaA2be8A07c6e0
AGENT007_KEY="0x0b6e18cafb6ed99687ec547bd28139cafdd2bffe70e6b688025de6b445aa5c5b" #0x798d4Ba9baf0064Ec19eB4F0a1a45785ae9D6DFc
MEMBER_1="0x39539ab1876910bbf3a223d84a29e28f1cb4e2e456503e7e91ed39b2e7223d68" #0x773539d4Ac0e786233D90A233654ccEE26a613D9
MEMBER_2="0x7dce9bc8babb68fec1409be38c8e1a52650206a7ed90ff956ae8a6d15eeaaef4" #0xFf64d3F6efE2317EE2807d223a0Bdc4c0c49dfDB
MEMBER_3="0xb9d2ea9a615f3165812e8d44de0d24da9bbd164b65c4f0573e1ce2c8dbd9c8df" #0xC0F0f4ab324C46e55D02D0033343B4Be8A55532d
NONMEMBER_1="0x96b8a38e12e1a31dee1eab2fffdf9d9990045f5b37e44d8cc27766ef294acf18" #0x7BF369283338E12C90514468aa3868A551AB2929
NONMEMBER_2="0x0d6dcaaef49272a5411896be8ad16c01c35d6f8c18873387b71fbc734759b0ab" #0x931f3600a299fd9B24cEfB3BfF79388D19804BeA
NONMEMBER_3="0x4c42532034540267bf568198ccec4cb822a025da542861fcb146a5fab6433ff8" #0xC41C5F1123ECCd5ce233578B2e7ebd5693869d73
REWARDS="0x94c49300a58d576011096bcb006aa06f5a91b34b4383891e8029c21dc39fbb8b" #0x2898FE7a42Be376C8BC7AF536A940F7Fd5aDd423
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