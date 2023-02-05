const StakingPool = artifacts.require("StakingPool");
const TokenLiquidStaking = artifacts.require("TokenLiquidStaking");

module.exports = async (deployer, network, accounts) => {

  require('dotenv').config()

  const _undelegationCollatorQueueMaxIter = process.env.UndelegationCollatorQueueMaxIter;
  const _daoDelegationQueueMaxIter = process.env.DaoDelegationQueueMaxIter;
  const _roundUnscheduledUndelegationsMaxIter = process.env.RoundUnscheduledUndelegationsMaxIter;
  const _tokenLiquidStakingInitialSupply = web3.utils.toWei(process.env.TokenLiquidStakingInitialSupply, "ether");

  const superior = accounts[0];
  console.log(`Superior is ${superior}`);

  const ParachainStaking = '0x0000000000000000000000000000000000000800';

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

  console.log(`Initializing StakingPool`);
  await SP.initialize(
    ParachainStaking,
    _DaoStaking,
    _TokenLiquidStaking,
    _MemberTreasury,
    _undelegationCollatorQueueMaxIter,
    _daoDelegationQueueMaxIter,
    _roundUnscheduledUndelegationsMaxIter,
    {value: _tokenLiquidStakingInitialSupply}
  );
  
  console.log('Finished deploying and intializing contracts')

  console.log("Contracts created:")
  console.log({    
    _StakingPool,
    _TokenLiquidStaking
  })

  console.log("Accounts used:")
  console.log({ accounts })

};
