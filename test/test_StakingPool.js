// Example test script - Uses Mocha and Ganache
const StakingPool = artifacts.require("mocks/StakingPool_mock.sol");
const Claimable = artifacts.require("Claimable.sol");
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
    let mt, sp, ca, tls, st;
    const [manager, officer, delegator1, delegator2, delegator3, agent007, rewards] = accounts;
    const _collator = process.env.Collator;
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

        sp = await StakingPool.new();
        assert.ok(sp);

        tls = await TokenLiquidStaking.new(_tokenLiquidStakingInitialSupply);
        assert.ok(tls);

        ca = await Claimable.new();
        assert.ok(ca);


        console.log(`Initializing StakingPool`);
        await sp.initialize(
          _collator,
          ps.address,
          tls.address,
          ca.address,
          {value: _tokenLiquidStakingInitialSupply}
        );
        const lstMaxLST = new BN(web3.utils.toWei("1000000", "ether"));
        await sp.setMaxLST(lstMaxLST, {from: manager});
      
        console.log(`Initializing Claimable`);      
        await ca.initialize(sp.address)
      
        console.log(`Initializing TokenLiquidStaking`)
        await tls.initialize(sp.address);

    })

    async function getLedgerDelegatedTotal(candidates) {
        const ledgersLength = await sp.getLedgersLength();
        let delegatedTotal = 0;
        for (let i = 0; i < ledgersLength; i++) {
            const ledger = await sp.ledgers(i);
            for (const candidate of candidates) {
                const ledgerDelegation = await st.delegationAmount(ledger, candidate);
                delegatedTotal += ledgerDelegation;
            }
        }
        return delegatedTotal;
    }

    async function getLedgerReducibleTotal() {
        const ledgersLength = await sp.getLedgersLength();
        let reducibleTotal = 0;
        for (let i = 0; i < ledgersLength; i++) {
            const ledger = await sp.ledgers(i);
            const reducible = await web3.eth.getBalance(ledger.address);
            reducibleTotal += reducible;
        }
        return reducibleTotal;
    }

    it("have all variables initialized", async () => {
        expect(await sp.COLLATOR()).to.be.equal(_collator);
        expect(await tls.totalSupply()).to.be.bignumber.equal(_tokenLiquidStakingInitialSupply);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(_tokenLiquidStakingInitialSupply);
    });


    /********* STAKING WITHOUT REWARDS */

    it("user depositing zero tokens should fail", async () => {
        const userDeposit = new BN(web3.utils.toWei("0", "ether"));
        return expect(sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit})).to.be.rejectedWith('ZERO_PAYMENT');
    });

    it("user trying to withdraw more than deposited should fail", async () => {
        const userDeposit = new BN(web3.utils.toWei("10", "ether"));
        const userWithdraw = userDeposit.add(new BN("1"));
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit});
        return expect(sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw, {from: delegator1})).to.be.rejectedWith("INS_BALANCE");
    });

    it("user trying to withdraw zero amount should fail", async () => {
        const userDeposit = new BN(web3.utils.toWei("10", "ether"));
        const userWithdraw = new BN("0");
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit});
        return expect(sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw, {from: delegator1})).to.be.rejectedWith("ZERO_AMOUNT");
    });

    it("user depositing an amount should return the right number of LS tokens", async () => {
        const userDeposit = new BN(web3.utils.toWei("3", "ether"));
        const lstBalance = userDeposit; // 1:1
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit});
        return expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(lstBalance);
    });

   
    it("multiple users depositing different amounts (no rewards) should not affect base rate", async () => {
        const base = new BN(web3.utils.toWei("1", "ether"));
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("2", "ether"));
        const userDeposit3 = new BN(web3.utils.toWei("11", "ether"));
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(base);
        expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(base);
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator2, value: userDeposit2});
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator3, value: userDeposit3});
        await sp.rebase({from: agent007});
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(base);
        return expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(base);
    });

    it("multiple users depositing and scheduling withdrawing (no rewards) should not affect base rate", async () => {
        const base = new BN(web3.utils.toWei("1", "ether"));
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("2", "ether"));
        const userDeposit3 = new BN(web3.utils.toWei("11", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const userWithdraw2 = new BN(web3.utils.toWei("1", "ether"));
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(base);
        expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(base);
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator2, value: userDeposit2});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator3, value: userDeposit3});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw2, {from: delegator2});
        await sp.rebase({from: manager});
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
        await sp.rebase({form: delegator1});
        expect(await sp.delegatedTotal()).to.be.bignumber.equal(expectedDelegatedTotal);
        expect(await sp.inUndelegation()).to.be.bignumber.equal(zero);
        expect(await sp.claimed()).to.be.bignumber.equal(zero);
        return expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
    });

    it("multiple users depositing and withdrawing different amounts (no rewards) should update pendingDelegation and pendingSchedulingUndelegation, and not affect toClaim and base rates", async () => {
        const user1 = delegator1;
        const user2 = delegator2;
        const user3 = delegator3;
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("2", "ether"));
        const userDeposit3 = new BN(web3.utils.toWei("11", "ether"));
        const depositsTotal = userDeposit1.add(userDeposit2).add(userDeposit3);

        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const userWithdraw2 = new BN(web3.utils.toWei("1", "ether"));
        const expectedInUndelegation = userWithdraw1.add(userWithdraw2);
        const expectedUnderlyingPerLSToken = new BN(web3.utils.toWei("1", "ether"));
        const expectedLSTokenPerUnderlying = new BN(web3.utils.toWei("1", "ether"));
        
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(expectedUnderlyingPerLSToken);
        expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(expectedLSTokenPerUnderlying);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(zero);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(zero);
        expect(await sp.pendingSchedulingUndelegation()).to.be.bignumber.equal(zero);
        expect(await sp.toClaim()).to.be.bignumber.equal(zero);

        await sp.delegatorStakeAndReceiveLSTokens({from: user1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: user2, value: userDeposit2});
        await sp.delegatorStakeAndReceiveLSTokens({from: user3, value: userDeposit3});

        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(depositsTotal);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(depositsTotal);
        expect(await sp.pendingSchedulingUndelegation()).to.be.bignumber.equal(zero);
        expect(await sp.toClaim()).to.be.bignumber.equal(zero);

        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: user1});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw2, {from: user2});

        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(depositsTotal);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(depositsTotal);
        expect(await sp.pendingSchedulingUndelegation()).to.be.bignumber.equal(expectedInUndelegation);
        expect(await sp.toClaim()).to.be.bignumber.equal(expectedInUndelegation);

        await sp.rebase({from: agent007});
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(depositsTotal);
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(depositsTotal);
        expect(await sp.pendingSchedulingUndelegation()).to.be.bignumber.equal(expectedInUndelegation);
        expect(await sp.toClaim()).to.be.bignumber.equal(expectedInUndelegation);
        expect(await sp.underlyingPerLSToken()).to.be.bignumber.equal(expectedUnderlyingPerLSToken);
        return expect(await sp.lstokenPerUnderlying()).to.be.bignumber.equal(expectedLSTokenPerUnderlying);
    });

    it("user making one delegation and scheduling an undelegation, then netting out", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const expectedPendingDelegation = userDeposit1.sub(userWithdraw1);
        const expectedPendingUndelegation = zero;

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        await sp.netOutPending({from: manager})
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(expectedPendingDelegation);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);
        return expect(await sp.pendingSchedulingUndelegation()).to.be.bignumber.equal(expectedPendingUndelegation);
    });

    it("one user making one delegation and scheduling an undelegation, then netting out a specific amount", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("3", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const netout = new BN(web3.utils.toWei("1", "ether"));
        const expectedPendingDelegation = userDeposit1.sub(netout);
        const expectedPendingUndelegation = userWithdraw1.sub(netout);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        await sp.netOutPendingAmount(netout, {from: manager})
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(expectedPendingDelegation);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);
        return expect(await sp.pendingSchedulingUndelegation()).to.be.bignumber.equal(expectedPendingUndelegation);
    });

    it("one user making one delegation and then making part of that claimable", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("5", "ether"));
        const makeClaimableAmount = new BN(web3.utils.toWei("3", "ether"));
        const expectedPendingDelegation = userDeposit1.sub(makeClaimableAmount);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.makeClaimable(makeClaimableAmount, {from: manager})
        expect(await sp.pendingDelegation()).to.be.bignumber.equal(expectedPendingDelegation);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);
        return expect(await sp.pendingSchedulingUndelegation()).to.be.bignumber.equal(zero);
    });

    it("user depositing, scheduling and executing withdrawal (no rewards), check TLS and balances before and after", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("6", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const expectedLSTForDeposit = userDeposit1;
        const expectedLSTAfterWithdrawal = userDeposit1.sub(userWithdraw1);
        const expectedBalanceAfterWithdrawal = userWithdraw1;

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTForDeposit);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        await sp.netOutPending({from: manager});
        await sp.executeUndelegations(1, {from: manager});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(expectedBalanceAfterWithdrawal);        
    });

    it("multiple users depositing, withdrawing and executing (no rewards), check TLS and balances before and after", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("8", "ether"));
        const userDeposit2 = new BN(web3.utils.toWei("5", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("3", "ether"));
        const userWithdraw2 = new BN(web3.utils.toWei("1", "ether"));
        const expectedLSTForDeposit = userDeposit1.add(userDeposit2);
        const expectedBalanceForDeposit = userDeposit1.add(userDeposit2);
        const expectedLSTAfterWithdrawal = expectedLSTForDeposit.sub(userWithdraw1).sub(userWithdraw2);
        const expectedBalanceAfterWithdrawal = expectedLSTAfterWithdrawal; // 1:1

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator2, value: userDeposit2});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTForDeposit);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(expectedBalanceForDeposit);

        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw2, {from: delegator2});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(expectedBalanceForDeposit);

        await sp.netOutPending({from: manager});
        await sp.executeUndelegations(2, {from: manager});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(expectedBalanceAfterWithdrawal); 
    });

    /********* TRANSFERS TO/FROM LEDGERS */

    it("pool can transfer to and from ledger", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("8", "ether"));
        const ledger0 = await sp.ledgers(0);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        await sp.depositToLedger(0, userDeposit1, {from: manager});
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(zero);
        expect(await web3.eth.getBalance(ledger0)).to.be.bignumber.equal(userDeposit1);

        await sp.withdrawFromLedger(0, userDeposit1, {from: manager});
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);
        expect(await web3.eth.getBalance(ledger0)).to.be.bignumber.equal(zero);
    });

    it("pool can transfer to and from second ledger", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("8", "ether"));

        await sp.addLedger();
        const ledger1 = await sp.ledgers(1);
        expect(ledger1).to.be.not.equal(ZERO_ADDR);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        await sp.depositToLedger(1, userDeposit1, {from: manager});
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(zero);
        expect(await web3.eth.getBalance(ledger1)).to.be.bignumber.equal(userDeposit1);

        await sp.withdrawFromLedger(1, userDeposit1, {from: manager});
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);
        expect(await web3.eth.getBalance(ledger1)).to.be.bignumber.equal(zero);
    });

    it("add/remove ledger", async () => {
        await sp.addLedger(); // add second ledger
        const ledger1 = await sp.ledgers(1);
        await sp.removeLedger(0);
        expect(await sp.ledgers(0)).to.be.equal(ledger1);
    });

    it("deposit and delegate through ledger", async () => {
        const candidate1 = ONE_ADDR;
        const ledger0 = await sp.ledgers(0);
        const userDeposit1 = new BN(web3.utils.toWei("7", "ether"));
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositAndDelegate(0, candidate1, userDeposit1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
    });
    
    it("deposit, delegate and revoke through ledger", async () => {
        const candidate1 = ONE_ADDR;
        const ledger0 = await sp.ledgers(0);
        const userDeposit1 = new BN(web3.utils.toWei("7", "ether"));
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositAndDelegate(0, candidate1, userDeposit1);
        await sp.scheduleRevokeDelegation(0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await st.executeDelegationRequest(ledger0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(zero);
    });

    it("deposit, delegate and undelegate through ledger", async () => {
        const candidate1 = ONE_ADDR;
        const ledger0 = await sp.ledgers(0);
        const userDeposit1 = new BN(web3.utils.toWei("7", "ether"));
        const bondLess = new BN(web3.utils.toWei("3", "ether"));
        const delegationAfterBondLess = userDeposit1.sub(bondLess);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositAndDelegate(0, candidate1, userDeposit1);
        await sp.scheduleDelegatorBondLess(0, candidate1, bondLess);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await st.executeDelegationRequest(ledger0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(delegationAfterBondLess);
    });

    it("deposit, delegate and undelegate through second ledger", async () => {
        const candidate1 = ONE_ADDR;
        await sp.addLedger();
        const ledger1 = await sp.ledgers(1);
        const userDeposit1 = new BN(web3.utils.toWei("11", "ether"));
        const bondLess = new BN(web3.utils.toWei("3", "ether"));
        const delegationAfterBondLess = userDeposit1.sub(bondLess);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositAndDelegate(1, candidate1, userDeposit1);
        await sp.scheduleDelegatorBondLess(1, candidate1, bondLess);
        expect(await st.delegationAmount(ledger1, candidate1)).to.be.bignumber.equal(userDeposit1);
        await st.executeDelegationRequest(ledger1, candidate1);
        expect(await st.delegationAmount(ledger1, candidate1)).to.be.bignumber.equal(delegationAfterBondLess);
    });

    it("deposit, delegate, revoke and cancel through ledger", async () => {
        const candidate1 = ONE_ADDR;
        const ledger0 = await sp.ledgers(0);
        const userDeposit1 = new BN(web3.utils.toWei("7", "ether"));
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositAndDelegate(0, candidate1, userDeposit1);
        await sp.scheduleRevokeDelegation(0, candidate1);
        await sp.cancelDelegationRequest(0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await st.executeDelegationRequest(ledger0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
    });

    it("deposit, delegate with compound, undelegate and cancel through ledger", async () => {
        const candidate1 = ONE_ADDR;
        const ledger0 = await sp.ledgers(0);
        const userDeposit1 = new BN(web3.utils.toWei("16", "ether"));
        const bondLess = new BN(web3.utils.toWei("6", "ether"));
        const delegationAfterBondLess = userDeposit1.sub(bondLess);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositToLedger(0, userDeposit1);
        await sp.delegateWithAutoCompound(0, candidate1, userDeposit1, "100");

        await sp.scheduleDelegatorBondLess(0, candidate1, bondLess);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await sp.cancelDelegationRequest(0, candidate1);
        await st.executeDelegationRequest(ledger0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);

        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await st.executeDelegationRequest(ledger0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(delegationAfterBondLess);
    });

    it("deposit, delegate with compound, undelegate and cancel through ledger (2)", async () => {
        const candidate1 = ONE_ADDR;
        const ledger0 = await sp.ledgers(0);
        const userDeposit1 = new BN(web3.utils.toWei("18", "ether"));
        const bondLess = new BN(web3.utils.toWei("5", "ether"));
        const delegationAfterBondLess = userDeposit1.sub(bondLess);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositAndDelegateWithAutoCompound(0, candidate1, userDeposit1, "100");

        await sp.scheduleDelegatorBondLess(0, candidate1, bondLess);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await sp.cancelDelegationRequest(0, candidate1);
        await st.executeDelegationRequest(ledger0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);

        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await st.executeDelegationRequest(ledger0, candidate1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(delegationAfterBondLess);
    });

    it("deposit, delegate and bond more through ledger", async () => {
        const candidate1 = ONE_ADDR;
        const ledger0 = await sp.ledgers(0);
        const userDeposit1 = new BN(web3.utils.toWei("7", "ether"));
        const bondMore = new BN(web3.utils.toWei("3", "ether"));
        const delegationAfterBondMore = userDeposit1.add(bondMore);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        await sp.depositAndDelegate(0, candidate1, userDeposit1);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(userDeposit1);
        await sp.delegatorStakeAndReceiveLSTokens({from: delegator2, value: bondMore});
        await sp.depositAndBondMore(0, candidate1, bondMore);
        expect(await st.delegationAmount(ledger0, candidate1)).to.be.bignumber.equal(delegationAfterBondMore);
    });

    /********* STAKING WITH REWARDS */

    it("user depositing, scheduling and executing withdrawal (with rewards), check TLS and balances before and after", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("6", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("2", "ether"));
        const rewardAmount = new BN(web3.utils.toWei("3", "ether"));       
        const expectedLSTForDeposit = userDeposit1; // at 1:1
        const expectedLSTAfterWithdrawal = userDeposit1.sub(userWithdraw1);
        const expectedBalanceAfterWithdrawal = (userWithdraw1.mul(rewardAmount).div(userDeposit1)).add(userWithdraw1);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTForDeposit);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        // simulate rewards
        await web3.eth.sendTransaction({ to: sp.address, from: rewards, value: rewardAmount });
        await sp.rebase({from: agent007});

        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        await sp.netOutPending({from: manager});
        await sp.executeUndelegations(1, {from: manager});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(expectedBalanceAfterWithdrawal);        
    });

    it("user depositing, scheduling and executing withdrawal (with rewards), check TLS and balances before and after (2)", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("6", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("6", "ether"));
        const rewardAmount = new BN(web3.utils.toWei("3", "ether"));       
        const expectedLSTForDeposit = userDeposit1; // at 1:1
        const expectedLSTAfterWithdrawal = userDeposit1.sub(userWithdraw1);
        const expectedBalanceAfterWithdrawal = (userWithdraw1.mul(rewardAmount).div(userDeposit1)).add(userWithdraw1);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTForDeposit);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        // simulate rewards
        await web3.eth.sendTransaction({ to: sp.address, from: rewards, value: rewardAmount });
        await sp.rebase({from: agent007});

        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        await sp.netOutPending({from: manager});
        await sp.executeUndelegations(1, {from: manager});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(expectedBalanceAfterWithdrawal);        
    });

    it("user depositing, scheduling and executing withdrawal (with rewards as bonus), check TLS and balances before and after", async () => {
        const userDeposit1 = new BN(web3.utils.toWei("7", "ether"));
        const userWithdraw1 = new BN(web3.utils.toWei("3", "ether"));
        const rewardAmount = new BN(web3.utils.toWei("4", "ether"));       
        const expectedLSTForDeposit = userDeposit1; // at 1:1
        const expectedLSTAfterWithdrawal = userDeposit1.sub(userWithdraw1);
        const expectedBalanceAfterWithdrawal = (userWithdraw1.mul(rewardAmount).div(userDeposit1)).add(userWithdraw1);

        await sp.delegatorStakeAndReceiveLSTokens({from: delegator1, value: userDeposit1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTForDeposit);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        // simulate rewards bonus
        await sp.depositAsBonus({from: manager, value: rewardAmount});
        await sp.rebase({from: agent007});

        await sp.delegatorScheduleUnstakeAndBurnLSTokens(userWithdraw1, {from: delegator1});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(userDeposit1);

        await sp.netOutPending({from: manager});
        await sp.executeUndelegations(1, {from: manager});
        expect(await tls.balanceOf(delegator1)).to.be.bignumber.equal(expectedLSTAfterWithdrawal);
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(expectedBalanceAfterWithdrawal);        
    });

    return;

    it("", async () => {
        
    });


})