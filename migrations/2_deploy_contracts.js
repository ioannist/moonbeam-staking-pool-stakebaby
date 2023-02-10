const StakingPool = artifacts.require("StakingPool");
const TokenLiquidStaking = artifacts.require("TokenLiquidStaking");
const Claimable = artifacts.require("Claimable.sol");

module.exports = async (deployer, network, accounts) => {

  require('dotenv').config()

  const _collator = process.env.Collator;
  const _tokenLiquidStakingInitialSupply = web3.utils.toWei(process.env.TokenLiquidStakingInitialSupply, "ether");

  const superior = accounts[0];
  console.log(`Superior is ${superior}`);

  const _ParachainStaking = '0x0000000000000000000000000000000000000800';

  console.log(`Deploying TokenLiquidStaking`);
  let _TokenLiquidStaking, TLS;
  while (true) {
    try {
      await deployer.deploy(TokenLiquidStaking, _tokenLiquidStakingInitialSupply);
      TLS = await TokenLiquidStaking.deployed();
      _TokenLiquidStaking = TLS.address;
      break;
    } catch { }
  }
  
  console.log(`Deploying StakingPool`);
  let _StakingPool, SP;
  while (true) {
    try {
      await deployer.deploy(StakingPool);
      SP = await StakingPool.deployed();
      _StakingPool = SP.address;
      break;
    } catch { }
  }

  console.log(`Deploying Claimable`);
  let _Claimable, CA;
  while (true) {
    try {
      await deployer.deploy(Claimable);
      CA = await Claimable.deployed();
      _Claimable = CA.address;
      break;
    } catch { }
  }

  console.log(`Initializing StakingPool`);
  await SP.initialize(
    _collator,
    _ParachainStaking,
    _TokenLiquidStaking,
    _Claimable,
    {value: _tokenLiquidStakingInitialSupply}
  );

  console.log(`Initializing Claimable`);

  await CA.initialize(_StakingPool)

  console.log(`Initializing TokenLiquidStaking`)
  await TLS.initialize(_StakingPool);
  
  console.log('Finished deploying and intializing contracts')

  console.log("Contracts created:")
  console.log({    
    _StakingPool,
    _TokenLiquidStaking
  })

  console.log("Accounts used:")
  console.log({ accounts })

};
