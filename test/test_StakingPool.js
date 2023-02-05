// Example test script - Uses Mocha and Ganache
const DaoMembership = artifacts.require("DaoMembership");
const DaoStaking = artifacts.require("DaoStaking");
const MemberTreasury = artifacts.require("mocks/MemberTreasury_mock.sol");
const Queue = artifacts.require("types/Queue.sol");
const StakingPool = artifacts.require("mocks/StakingPool_mock.sol");
const TokenDao = artifacts.require("TokenDao");
const TokenLiquidStaking = artifacts.require("TokenLiquidStaking");
const Staking = artifacts.require("mocks/Staking_mock.sol")

const chai = require("chai");
const BN = require('bn.js');
const chaiBN = require("chai-bn")(BN);
chai.use(chaiBN);

const chaiAsPromised = require("chai-as-promised");
const { assert } = require("chai");
const { locStart } = require("prettier-plugin-solidity/src/loc");
chai.use(chaiAsPromised);

const expect = chai.expect;

contract('StakingPool', accounts => {

    require('dotenv').config()
    let dm, ds, mt, sp, td, tls, qu, st;
    const [daoStaking, daoMembers, agent007, member1, member2, member3, nonMember1, nonMember2, nonMember3, rewards] = accounts;
    const _undelegationCollatorQueueMaxIter = process.env.UndelegationCollatorQueueMaxIter;
    const _daoDelegationQueueMaxIter = process.env.DaoDelegationQueueMaxIter;
    const _roundUnscheduledUndelegationsMaxIter = process.env.RoundUnscheduledUndelegationsMaxIter;
    const _tokenLiquidStakingInitialSupply = web3.utils.toWei(process.env.TokenLiquidStakingInitialSupply, "ether");
    const ZERO_ADDR = "0x0000000000000000000000000000000000000000";
    const ONE_ADDR = "0x0000000000000000000000000000000000000001";
    const TWO_ADDR = "0x0000000000000000000000000000000000000002";
    const THREE_ADDR = "0x0000000000000000000000000000000000000003";
    const zero = new BN("0")

    function bnToEther(bignumber) {
        return new BN(bignumber).div(new BN(web3.utils.toWei("1", "ether"))).toNumber()
    }

    async function makeRewards(amount) {
        await web3.eth.sendTransaction({ to: sp.address, from: rewards, value: amount });
    }

    beforeEach(async () => {

        console.log(`Creating contracts`);
        st = await Staking.new();
        assert.ok(st);

        mt = await MemberTreasury.new();
        assert.ok(mt);

        qu = await Queue.new();
        assert.ok(qu);

        await StakingPool.link("Queue", qu.address);

        sp = await StakingPool.new();
        assert.ok(sp);

        td = await TokenDao.new();
        assert.ok(td);

        dm = await DaoMembership.new(td.address);
        assert.ok(dm);

        tls = await TokenLiquidStaking.new(_tokenLiquidStakingInitialSupply);
        assert.ok(tls);

        ds = await DaoStaking.new(tls.address);
        assert.ok(ds);

        console.log(`Initializing StakingPool`);
        await sp.initialize(
          st.address,
          daoStaking, // in production, this is ds.address for DAO ownership
          tls.address,
          mt.address,
          _undelegationCollatorQueueMaxIter,
          _daoDelegationQueueMaxIter,
          _roundUnscheduledUndelegationsMaxIter,
          {value: _tokenLiquidStakingInitialSupply}
        );
                
        console.log(`Initializing MemberTreasury`);
        await mt.initialize_mock(
            st.address,
            daoMembers, // in production this is dm.address for DAO ownership
            sp.address,
            td.address,
            tls.address,
            // we initialize we 2 non-members, and let nonMember3 out for now
            nonMember1,
            nonMember2,
            member1,
            member2,
        );
      
        console.log(`Initializing TokenDao`);
        await td.initialize(dm.address, mt.address);
      
        console.log(`Initializing TokenLiquidStaking`);
        await tls.initialize(sp.address, ds.address);

        await mt.upgradeNonMemberToMember(member1, {from: daoMembers})
        await mt.upgradeNonMemberToMember(member2, {from: daoMembers})
    })

    it("have all variables initialized", async () => {
        expect(await sp.undelegationCollatorQueueMaxIter()).to.be.bignumber.equal(_undelegationCollatorQueueMaxIter);
        expect(await sp.daoDelegationQueueMaxIter()).to.be.bignumber.equal(_daoDelegationQueueMaxIter);
        expect(await sp.roundUnscheduledUndelegationsMaxIter()).to.be.bignumber.equal(_roundUnscheduledUndelegationsMaxIter);
        expect(await tls.totalSupply()).to.be.bignumber.equal(_tokenLiquidStakingInitialSupply);
    });


    /********* STAKING WITHOUT REWARDS */

    it("user depositing zero tokens should fail", async () => {
        const userDeposit = new BN(web3.utils.toWei("0", "ether"));
        return expect(sp.delegatorStakeAndReceiveLSTokens({from: agent007, value: userDeposit})).to.be.rejectedWith('ZERO_PAYMENT');
    });

    it("user trying to withdraw more than deposited should fail", async () => {
        const userDeposit = new BN(web3.utils.toWei("10", "ether"));
        const userWithdraw = userDeposit.add(new BN("1"));
        await sp.delegatorStakeAndReceiveLSTokens({from: agent007, value: userDeposit});
        return expect(sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw, {from: agent007})).to.be.rejectedWith("INS_BALANCE");
    });

    it("user trying to withdraw zero amount should fail", async () => {
        const userDeposit = new BN(web3.utils.toWei("10", "ether"));
        const userWithdraw = new BN("0");
        await sp.delegatorStakeAndReceiveLSTokens({from: agent007, value: userDeposit});
        return expect(sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw, {from: agent007})).to.be.rejectedWith("ZERO_AMOUNT");
    });

    it("user depositing an amount should return the right number of LS tokens", async () => {
        const userDeposit = new BN(web3.utils.toWei("3", "ether"));
        const lstBalance = userDeposit; // 1:1
        await sp.delegatorStakeAndReceiveLSTokens({from: agent007, value: userDeposit});
        return expect(await tls.balanceOf(agent007)).to.be.bignumber.equal(lstBalance);
    });

    it("user depositing from member treasury should increase bootstrap amount", async () => {
        const mintAllowance = new BN(web3.utils.toWei("1000", "ether"));
        const mint = new BN(web3.utils.toWei("50", "ether"))
        const bootstrap = mint;
        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        // add some tokens to the members treasury by minting DAO tokens
        await mt.mintDaoTokens({from: member1, value: mint});
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(mint);
        // bootstrap
        await mt.bootstrap(bootstrap, {from: daoMembers});
        return expect(await sp.bootstrapDeposits()).to.be.bignumber.equal(bootstrap);
    });
    
    it("multiple users depositing different amounts (no rewards) should not affect base rate", async () => {
        const base = new BN(web3.utils.toWei("1", "ether"));
        const user1 = agent007;
        const user2 = nonMember2; // use non-member as a regular pool user
        const user3 = nonMember3; // use non-member as a regular pool user
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("2", "ether"));
        const userDeposit3 = new BN(web3.utils.toWei("11", "ether"));
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(base);
        expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(base);
        await sp.delegatorStakeAndReceiveLSTokens({from: user1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: user2, value: userDeposit2});
        await sp.delegatorStakeAndReceiveLSTokens({from: user3, value: userDeposit3});
        await sp.rebase();
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(base);
        return expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(base);
    });

    it("multiple users depositing and scheduling withdrawing (no rewards) should not affect base rate", async () => {
        const base = new BN(web3.utils.toWei("1", "ether"));
        const user1 = agent007;
        const user2 = nonMember2; // use non-member as a regular pool user
        const user3 = nonMember3; // use non-member as a regular pool user
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("2", "ether"));
        const userDeposit3 = new BN(web3.utils.toWei("11", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const userWithdraw2 = new BN(web3.utils.toWei("1", "ether"));
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(base);
        expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(base);
        await sp.delegatorStakeAndReceiveLSTokens({from: user1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: user2, value: userDeposit2});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: user1});
        await sp.delegatorStakeAndReceiveLSTokens({from: user3, value: userDeposit3});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw2, {from: user2});
        await sp.rebase();
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(base);
        return expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(base);
    });

    it("multiple users depositing different amounts (no rewards) should update delegatedTotal, and not affect inUndelegation, claimed, or pendingDelegation", async () => {
        const user1 = agent007;
        const user2 = nonMember2; // use non-member as a regular pool user
        const user3 = nonMember3; // use non-member as a regular pool user
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("2", "ether"));
        const userDeposit3 = new BN(web3.utils.toWei("11", "ether"));
        const expectedDelegatedTotal = userDeposit1.add(userDeposit2).add(userDeposit3);
        expect(await sp.delegatedTotal()).to.be.bignumber.equal(zero);
        expect(await sp.inUndelegation()).to.be.bignumber.equal(zero);
        expect(await sp.claimed()).to.be.bignumber.equal(zero);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
        await sp.delegatorStakeAndReceiveLSTokens({from: user1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: user2, value: userDeposit2});
        await sp.delegatorStakeAndReceiveLSTokens({from: user3, value: userDeposit3});
        expect(await sp.delegatedTotal()).to.be.bignumber.equal(expectedDelegatedTotal);
        expect(await sp.inUndelegation()).to.be.bignumber.equal(zero);
        expect(await sp.claimed()).to.be.bignumber.equal(zero);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
        await sp.rebase();
        expect(await sp.delegatedTotal()).to.be.bignumber.equal(expectedDelegatedTotal);
        expect(await sp.inUndelegation()).to.be.bignumber.equal(zero);
        expect(await sp.claimed()).to.be.bignumber.equal(zero);
        return expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
    });

    it("multiple users depositing and withdrawing different amounts (no rewards) should update delegatedTotal and inUndelegation, and not affect claimed, or pendingDelegation", async () => {
        const user1 = agent007;
        const user2 = nonMember2; // use non-member as a regular pool user
        const user3 = nonMember3; // use non-member as a regular pool user
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("2", "ether"));
        const userDeposit3 = new BN(web3.utils.toWei("11", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const userWithdraw2 = new BN(web3.utils.toWei("1", "ether"));
        const expectedDelegatedTotal =
            userDeposit1.add(userDeposit2).add(userDeposit3)
            .sub(userWithdraw1).sub(userWithdraw2);
        const expectedInUndelegation = userWithdraw1.add(userWithdraw2);
        expect(await sp.delegatedTotal()).to.be.bignumber.equal(zero);
        expect(await sp.inUndelegation()).to.be.bignumber.equal(zero);
        expect(await sp.claimed()).to.be.bignumber.equal(zero);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
        await sp.delegatorStakeAndReceiveLSTokens({from: user1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: user2, value: userDeposit2});
        await sp.delegatorStakeAndReceiveLSTokens({from: user3, value: userDeposit3});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: user1});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw2, {from: user2});

        expect(await sp.delegatedTotal()).to.be.bignumber.equal(expectedDelegatedTotal);
        expect(await sp.inUndelegation()).to.be.bignumber.equal(expectedInUndelegation);
        expect(await sp.claimed()).to.be.bignumber.equal(zero);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
        await sp.rebase();
        expect(await sp.delegatedTotal()).to.be.bignumber.equal(expectedDelegatedTotal);
        expect(await sp.inUndelegation()).to.be.bignumber.equal(expectedInUndelegation);
        expect(await sp.claimed()).to.be.bignumber.equal(zero);
        return expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
    });

    return;

    it("mulitple users depositing and withdrawing (no rewards) should not affect base rate", async () => {
        
    });

    it("multiple users depositing and scheduling withdrawing (no rewards) should be promised the correct underlying amounts", async () => {
        
    });

    it("mulitple users depositing and withdrawing (no rewards) should be given the correct underlying amounts", async () => {
        
    });

    /********* STAKING WITH REWARDS */

    it("rewards should increase the base rate", async () => {
        
    });

    it("user depositing after rewards+rebasing should have the right base rate", async () => {
        
    });

    it("user depositing after rewards (but no rebasing) should have the right base rate", async () => {
        
    });



    it("", async () => {
        
    });

    it("", async () => {
        
    });

    it("", async () => {
        
    });

    it("", async () => {
        
    });

    it("", async () => {
        
    });

    it("", async () => {
        
    });
})