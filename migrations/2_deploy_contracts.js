const StakingPool = artifacts.require("StakingPool");
const TokenLiquidStaking = artifacts.require("TokenLiquidStaking");
const Claimable = artifacts.require("Claimable.sol");
const Queue = artifacts.require("types/Queue.sol");
const BN = require('bn.js');

module.exports = async (deployer, network, accounts) => {

  require('dotenv').config()

  const _poolManager = process.env.POOL_MANAGER;
  const _tokenLiquidStakingInitialSupply = web3.utils.toWei(process.env.TokenLiquidStakingInitialSupply, "ether");

  const superior = accounts[0];
  const manager = accounts[1];
  console.log(`Superior is ${superior}`);

  const _ParachainStaking = '0x0000000000000000000000000000000000000800';
  const _Proxy = "0x000000000000000000000000000000000000080b";

  console.log(`Deploying Queue`);
  let _Queue, QU;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    try {
      await deployer.deploy(Queue);
      QU = await Queue.deployed();
      _Queue = QU.address;
      break;
    } catch { }
  }
  await deployer.link(Queue, StakingPool);

  console.log(`Deploying StakingPool`);
  let _StakingPool, SP;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    try {
      await deployer.deploy(StakingPool);
      SP = await StakingPool.deployed();
      _StakingPool = SP.address;
      break;
    } catch { }
  }

  console.log(`Deploying TokenLiquidStaking`);
  let _TokenLiquidStaking, TLS;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    try {
      await deployer.deploy(TokenLiquidStaking, _tokenLiquidStakingInitialSupply, _StakingPool);
      TLS = await TokenLiquidStaking.deployed();
      _TokenLiquidStaking = TLS.address;
      break;
    } catch { }
  }
  
  console.log(`Deploying Claimable`);
  let _Claimable, CA;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    try {
      await deployer.deploy(Claimable, _StakingPool);
      CA = await Claimable.deployed();
      _Claimable = CA.address;
      break;
    } catch { }
  }

  console.log(`Initializing StakingPool`);
  await new Promise(r => setTimeout(r, 2000));
  await SP.initialize(
    _poolManager,
    _ParachainStaking,
    _Proxy,
    _TokenLiquidStaking,
    _Claimable,
    {from: superior, value: _tokenLiquidStakingInitialSupply}
  );

  console.log(`Set skipRebase`);
  await new Promise(r => setTimeout(r, 2000));
  await SP.setSkipRebase(true, {from: manager});
  
  console.log('Finished deploying and intializing contracts')
  console.log("Contracts created:")
  console.log({    
    _StakingPool,
    _TokenLiquidStaking,
    _Claimable
  })

  console.log("Accounts used:")
  console.log({ accounts })

};
