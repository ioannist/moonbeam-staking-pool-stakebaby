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

const chaiAlmost = require('chai-almost');
chai.use(chaiAlmost(0.01));

const expect = chai.expect;

contract('MemberTreasury', accounts => {

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
        return new BN(bignumber).div(new BN(web3.utils.toWei("1", "ether")))
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

    return;

    it("dao can set token mint allowance", async () => {
        const mintAllowance = new BN(web3.utils.toWei("11", "ether"));
        expect(await mt.tokenDaoMintAllowance()).to.be.bignumber.equal(zero);
        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        return expect(await mt.tokenDaoMintAllowance()).to.be.bignumber.equal(mintAllowance);
    });

    it("dao can set welcome amount", async () => {
        const welcomeAmount = new BN(web3.utils.toWei("1001", "ether"));
        expect(await mt.welcomeAmount()).to.be.bignumber.equal(zero);
        await mt.setWelcomeAmount(welcomeAmount, {from: daoMembers});
        return expect(await mt.welcomeAmount()).to.be.bignumber.equal(welcomeAmount);
    });
    
    it("replacing non-member with same non-member should fail", async () => {
        // current non-memebers: nonMember1, nonMember2
        await expect(mt.replaceNonMemberCollator(nonMember1, nonMember1, {from: daoMembers})).to.be.rejectedWith("SAME");
    });
    
    it("replacing non-member with an address that is already a non-member should fail", async () => {
        await expect(mt.replaceNonMemberCollator(nonMember1, nonMember2, {from: daoMembers})).to.be.rejectedWith("NON_MEMBER_EXISTS");
    });

    it("replacing non-member with an address that is already a member should fail", async () => {
        await mt.upgradeNonMemberToMember(nonMember2, {from: daoMembers});
        await expect(mt.replaceNonMemberCollator(nonMember1, nonMember2, {from: daoMembers})).to.be.rejectedWith("MEMBER_EXISTS");
    });

    it("replacing a non-member that has non-zero delegations should fail", async () => {
        const delegations = web3.utils.toWei("1", "ether")
        await sp.setDelegations_mock(nonMember1, delegations, {from: daoStaking})
        await expect(mt.replaceNonMemberCollator(nonMember1, nonMember3, {from: daoMembers})).to.be.rejectedWith("DELEGATIONS_NOT_ZERO");
    });

    it("replacing a non-member that has non-zero undelegations should fail", async () => {
        const undelegations = web3.utils.toWei("1", "ether")
        await sp.setUndelegations_mock(nonMember1, undelegations, {from: daoStaking})
        await expect(mt.replaceNonMemberCollator(nonMember1, nonMember3, {from: daoMembers})).to.be.rejectedWith("UNDELEGATIONS_NOT_ZERO");
   });

    it("replacing a non-member should remove the non-member and add the new non-member", async () => {
        let nonMember1Id = await mt.getNonMemberId_mock(nonMember1);
        console.log({nonMember1Id: nonMember1Id.toString()})
        expect(await mt.getNonMember(nonMember1Id)).to.be.equal(nonMember1);
        const N_FOUND_mock = await mt.N_FOUND_mock();
        console.log({N_FOUND_mock: N_FOUND_mock.toString()})
        expect(await mt.getNonMemberId_mock(nonMember3)).to.be.bignumber.equal(N_FOUND_mock);

        await mt.replaceNonMemberCollator(nonMember1, nonMember3, {from: daoMembers});
        expect(await mt.getNonMember(nonMember1Id)).to.not.be.equal(nonMember1);
        expect(await mt.getNonMemberId_mock(nonMember1)).to.be.bignumber.equal(N_FOUND_mock);
        let nonMember3Id = await mt.getNonMemberId_mock(nonMember3);
        console.log({nonMember3Id: nonMember3Id.toString()})
        return expect(await mt.getNonMember(nonMember3Id)).to.be.equal(nonMember3);
    });

    it("replacing a non-member should mirror the add-remove effect in the stakingPool nonMembers", async () => {
        let nonMember1Id = await mt.getNonMemberId_mock(nonMember1);
        expect(await sp.nonMembers(nonMember1Id)).to.be.equal(nonMember1);
        const N_FOUND_mock = await mt.N_FOUND_mock();
        expect(await mt.getNonMemberId_mock(nonMember3)).to.be.bignumber.equal(N_FOUND_mock);

        await mt.replaceNonMemberCollator(nonMember1, nonMember3, {from: daoMembers});
        expect(await sp.nonMembers(nonMember1Id)).to.not.be.equal(nonMember1);
        expect(await mt.getNonMemberId_mock(nonMember1)).to.be.bignumber.equal(N_FOUND_mock);
        let nonMember3Id = await mt.getNonMemberId_mock(nonMember3);
        return expect(await sp.nonMembers(nonMember3Id)).to.be.equal(nonMember3);
    });

    it("upgrading non-member that does not exist should fail", async () => {
        return expect(mt.upgradeNonMemberToMember(nonMember3, {from: daoMembers})).to.be.rejectedWith("NON_MEMBER_NOT_FOUND");
    });
    
    it("upgrading non-member that is already a member, should fail", async () => {
        await mt.upgradeNonMemberToMember(nonMember1, {from: daoMembers})
        return expect(mt.upgradeNonMemberToMember(nonMember1, {from: daoMembers})).to.be.rejectedWith("NON_MEMBER_NOT_FOUND");
    });

    it("upgrading a non-member should remove it from non-members and add it to members", async () => {
        const newMember1 = nonMember1;
        const N_FOUND_mock = await mt.N_FOUND_mock();
        expect(await mt.getMemberId_mock(newMember1)).to.be.bignumber.equal(N_FOUND_mock);
        await mt.upgradeNonMemberToMember(nonMember1, {from: daoMembers})
        expect(await mt.getNonMemberId_mock(nonMember1)).to.be.bignumber.equal(N_FOUND_mock);
        let member1Id = await mt.getMemberId_mock(newMember1);
        return expect(await mt.getMember(member1Id)).to.be.equal(newMember1);
    });

    it("upgrading a non-member should mirror the add-remove effect in the stakingPool non-members and members", async () => {
        const newMember1 = nonMember1;
        const N_FOUND_mock = await mt.N_FOUND_mock();
        expect(await mt.getMemberId_mock(newMember1)).to.be.bignumber.equal(N_FOUND_mock);
        await mt.upgradeNonMemberToMember(nonMember1, {from: daoMembers})
        expect(await mt.getNonMemberId_mock(nonMember1)).to.be.bignumber.equal(N_FOUND_mock);
        let member1Id = await mt.getMemberId_mock(newMember1);
        return expect(await sp.members(member1Id)).to.be.equal(newMember1);
    });

    it("minting DAO tokens by a non-member should fail", async () => {
        const tokens = new BN(web3.utils.toWei("221", "ether"));
        return expect(mt.mintDaoTokens({from: nonMember1, value: tokens})).to.be.rejectedWith("MEMBER_NOT_EXISTS");
    });

    it("minting more DAO tokens than the allowance should fail", async () => {
        const mintAllowance = new BN(web3.utils.toWei("11", "ether"));
        const more = mintAllowance.add(new BN("1"))
        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        return expect(mt.mintDaoTokens({from: member1, value: more})).to.be.rejectedWith("EXCEEDS_ALLOWANCE");
    });

    it("minting more DAO token than the allowance (in 2 txs) should fail", async () => {
        const mintAllowance = new BN(web3.utils.toWei("11", "ether"));
        const mint1 = new BN(web3.utils.toWei("6", "ether"));
        const mint2 = new BN(web3.utils.toWei("6", "ether"))
        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        await mt.mintDaoTokens({from: member1, value: mint1});
        return expect(mt.mintDaoTokens({from: member1, value: mint2})).to.be.rejectedWith("EXCEEDS_ALLOWANCE");
    });

    it("minting DAO tokens should update the member's DAO token balance 1:1", async () => {
        const mintAllowance = new BN(web3.utils.toWei("11", "ether"));
        const mint = new BN(web3.utils.toWei("6", "ether"))
        const daoTokens = mint; // 1:1
        const balanceStart = new BN(await web3.eth.getBalance(member1));
        const balanceEnd = balanceStart.sub(mint);
        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        expect(await td.balanceOf(member1)).to.be.bignumber.equal(zero);
        await mt.mintDaoTokens({from: member1, value: mint});
        expect(await td.balanceOf(member1)).to.be.bignumber.equal(daoTokens);
        return expect(bnToEther(await web3.eth.getBalance(member1))).to.be.bignumber.almost.equal(bnToEther(balanceEnd));
    });

    it("depositing tokens to the staking pool should move the tokens from treasury to the pool", async () => {
        const mintAllowance = new BN(web3.utils.toWei("1000", "ether"));
        const mint = new BN(web3.utils.toWei("50", "ether"))
        const deposit = mint;
        const poolEndBalance = mint.add(new BN(_tokenLiquidStakingInitialSupply))

        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        // add some tokens to the members treasury by minting DAO tokens
        await mt.mintDaoTokens({from: member1, value: mint});
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(mint);
        // move all tokens to the pool
        await mt.depositToStakingPool(deposit, {from: daoMembers});
        // cofirm the members tresury sent the tokens
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(zero);
        // confirm the pool received the tokens
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(poolEndBalance);
        // confirm that the member treasury was not given any LS tokens in return
        return expect(await tls.balanceOf(mt.address)).to.be.bignumber.equal(zero);
    });

    it("bootstraping more than the available token balance should fail", async () => {
        const mintAllowance = new BN(web3.utils.toWei("1000", "ether"));
        const mint = new BN(web3.utils.toWei("50", "ether"))
        const bootstrap = mint.add(new BN("1"));

        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        // add some tokens to the members treasury by minting DAO tokens
        await mt.mintDaoTokens({from: member1, value: mint});
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(mint);
        // bootstrap
        return expect(mt.bootstrap(bootstrap, {from: daoMembers})).to.be.rejectedWith("INS_BALANCE");
    });

    it("bootstraping should decrease the treasury's token balance and increase its LS token balance", async () => {
        const mintAllowance = new BN(web3.utils.toWei("1000", "ether"));
        const mint = new BN(web3.utils.toWei("50", "ether"))
        const bootstrap = mint;
        const poolEndBalance = mint.add(new BN(_tokenLiquidStakingInitialSupply))

        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        // add some tokens to the members treasury by minting DAO tokens
        await mt.mintDaoTokens({from: member1, value: mint});
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(mint);
        // bootstrap
        await mt.bootstrap(bootstrap, {from: daoMembers});
        // cofirm the members treasury sent the tokens
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(zero);
        // confirm the pool received the tokens
        expect(await web3.eth.getBalance(sp.address)).to.be.bignumber.equal(poolEndBalance);
        // confirm that the member treasury was given LS tokens in return, 1:1
        return expect(await tls.balanceOf(mt.address)).to.be.bignumber.equal(bootstrap);
    });

    it("unbootstraping without having ever bootstrapped, should fail", async () => {
        const unbootstrap = new BN(web3.utils.toWei("1", "ether"));
        return expect(mt.scheduleUnbootstrap(unbootstrap, {from: daoMembers})).to.be.rejectedWith("INS_LST_BALANCE");
    });

    it("unbootstraping more than the treasury has bootstraped, should fail", async () => {
        const mintAllowance = new BN(web3.utils.toWei("1000", "ether"));
        const mint = new BN(web3.utils.toWei("50", "ether"))
        const bootstrap = mint;
        const unbootstrap = bootstrap.add(new BN("1"));
        
        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        // add some tokens to the members treasury by minting DAO tokens
        await mt.mintDaoTokens({from: member1, value: mint});
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(mint);
        // bootstrap
        await mt.bootstrap(bootstrap, {from: daoMembers});
        return expect(mt.scheduleUnbootstrap(unbootstrap, {from: daoMembers})).to.be.rejectedWith("INS_LST_BALANCE");
    });

    it("unbootstraping should decrease the LS token balance and not affect the token balance", async () => {
        const mintAllowance = new BN(web3.utils.toWei("1000", "ether"));
        const mint = new BN(web3.utils.toWei("50", "ether"))
        const bootstrap = mint;
        const unbootstrap = bootstrap;
        
        await mt.setTokenDaoMintAllowance(mintAllowance, {from: daoMembers});
        // add some tokens to the members treasury by minting DAO tokens
        await mt.mintDaoTokens({from: member1, value: mint});
        expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(mint);
        // bootstrap
        await mt.bootstrap(bootstrap, {from: daoMembers});
        // confirm that the member treasury was given LS tokens in return, 1:1
        expect(await tls.balanceOf(mt.address)).to.be.bignumber.equal(bootstrap);
        await mt.scheduleUnbootstrap(unbootstrap, {from: daoMembers});
        // confirm that the LS tokens were bunt 1:1
        expect(await tls.balanceOf(mt.address)).to.be.bignumber.equal(zero);
        // cofirm the token balance of tresury is still zero (tokens not returned yet)
        return expect(await web3.eth.getBalance(mt.address)).to.be.bignumber.equal(zero);
    });


})