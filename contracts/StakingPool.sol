// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import OpenZeppelin Contract
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ParachainStaking} from "./interfaces/StakingInterface.sol";
import {Proxy} from "./interfaces/Proxy.sol";
import {TokenLiquidStaking} from "./TokenLiquidStaking.sol";
import {Ledger} from "./Ledger.sol";
import {Claimable} from "./Claimable.sol";
import "./types/Queue.sol";

//********************* STAKING POOL *********************/

contract StakingPool is ReentrancyGuard {
    //Contract accounts
    address public PARACHAIN_STAKING;
    address public TOKEN_LIQUID_STAKING;
    address payable public CLAIMABLE;
    // User accounts
    address public MANAGER;

    // If a pending undelegation request takes more than this rounds to be served, then inLiquidation -> true
    uint256 public constant LIQUIDATION_ROUND_THRESHOLD = 4 * 60;
    // Max number of ledgers
    uint256 public constant MAX_LEDGER_COUNT = 100;

    // Missing ledger index
    uint256 internal constant N_FOUND = type(uint256).max;

    ParachainStaking staking;
    Proxy proxy;
    TokenLiquidStaking tokenLiquidStaking;
    Claimable claimable;

    // If the contract has not executed undelegation requests for longer than LIQUIDATION_ROUND_THRESHOLD rounds
    // then anybody can activate inLiquidation mode to allow the ledgers to undelegate and free up funds
    // This is a security feature to ensure delegators don't depend on the manager to reclaim their funds
    bool public inLiquidation;

    // Ledgers (contracts that stake on behalf of the pool contract)
    address payable[] public ledgers;

    // Last round that we called rebase on
    uint256 public lastRoundRebased;
    // Stops auto-rebasing on every new round (rebasing can still be called on-demand)
    bool public skipRebase;

    // Current exchange rate
    uint256 public underlyingPerLSToken = 1 ether; // 1:1 starting ratio
    uint256 public lstokenPerUnderlying = 1 ether; // 1:1 starting ratio

    // Current total claimed through delegator initiated undelegations that burnt the LS token leg.
    // Buffered incoming delegation requests
    int256 public pendingDelegation;
    // Buffered incoming undelegation requests
    int256 public pendingSchedulingUndelegation;
    // Ledger to candidate to last scheduled request
    mapping(address => mapping(address => uint256)) internal scheduledRequests;
    // toClaim is the amount of underlying that is excluded from the pool, and has its corresponding LS tokens burnt
    // This amount can be transfered to the claimable contract as soon as it is available in reducible balance
    uint256 public toClaim;
    // Convenience data structure for accessing pending claims per delegator
    mapping(address => uint256) public delegatorToClaims;

    // Max LST in circulation
    uint256 public MAX_LST_SUPPLY = 1_000_000 ether;
    // Max delegation per delegator; this can be easilly circumvented by users by simply transfering the LS tokens
    // to another address, so it's mostly used to disincentivize rather than deter large delegations by one user
    uint256 public MAX_DELEGATION_LST = 50_000 ether;

    // EVENTS
    event DelegatedToPool(address delegator, uint256 amount, uint256 lstAmount);
    event ScheduledUndelegateFromPool(
        address delegator,
        uint256 amount,
        uint256 lstAmount
    );
    event InLiquidationActivated();
    event InLiquidationDeactivated();
    event InLiquidationWithdrawal();
    event InLiquidationRevoke();
    event Rebase(uint256 underlyingPerLSToken, uint256 lstokenPerUnderlying);
    event UndelegationExecuted(address delegator, uint256 amount);
    event DepositedBonus(uint256 amount);
    event AddedLedger(address ledger);
    event RemovedLedger(address ledger);
    event DepositedToLedger(address ledger, uint256 amount);
    event WithdrawnFromLedger(address ledger, uint256 amount);
    event MadeClaimable(uint256 amount);
    event NetOutPending(int256 amount);
    event LedgerDelegate(address ledger, address candidate, uint256 amount);
    event LedgerBondMore(address ledger, address candidate, uint256 amount);
    event LedgerDelegateWithAutoCompound(
        address ledger,
        address candidate,
        uint256 amount
    );
    event LedgerBondLess(address ledger, address candidate, uint256 amount);
    event LedgerCancelDelegationRequest(address ledger, address _candidate);
    event LedgerAutoCompoundSet(address ledger, address candidate, uint8 value);
    event LedgerScheduledRevoke(address ledger, address _candidate);
    event MaxLstSupplySet(uint256 supply);
    event MaxDelegationLstSet(uint256 maxDelegation);
    event SkipRebaseSet(bool skipRebase);

    // Pending undelegation requests {who: delegator, amount: delegation, round}
    Queue.QueueStorage public undelegationQueue;

    modifier onlyManagerProxy() {
        require(_isProxy(msg.sender), "NOT_PROXY");
        _;
    }

    function initialize(
        address _manager,
        address _parachainStaking,
        address _proxy,
        address _tokenLiquidStaking,
        address payable _claimable
    ) external payable {
        require(
            _manager != address(0) && MANAGER == address(0),
            "ALREADY_INIT"
        );
        MANAGER = _manager;
        PARACHAIN_STAKING = _parachainStaking;
        TOKEN_LIQUID_STAKING = _tokenLiquidStaking;
        CLAIMABLE = _claimable;
        staking = ParachainStaking(PARACHAIN_STAKING);
        tokenLiquidStaking = TokenLiquidStaking(TOKEN_LIQUID_STAKING);
        claimable = Claimable(CLAIMABLE);
        proxy = Proxy(_proxy);
        // We must provide the initial underlying capital 1:1
        require(
            tokenLiquidStaking.totalSupply() == msg.value,
            "INV_INIT_CAPITAL"
        );
        Queue.initialize(undelegationQueue);
        _addLedger(); // add the first ledger
    }

    //********************* PUBLIC USER (DELEGATORS) METHODS *********************/

    /**
    @notice Delegators can send GLMR with this method to get the LS token
    @dev Deposits to this contract through this method will mint to the depositor the corresponding amount of LS tokens
    based on the current exchange rate. Deposits are delegated immediately, i.e. they don't sit in reducible balance.
    When we say "delegated immediately" we do not necessarilly mean that there is a delegation to a collator. The contract
    may cancel an undelegation instead, which is equivalent (and preferable) to making a new delegation.
    */
    function delegatorStakeAndReceiveLSTokens() public payable nonReentrant {
        require(msg.value > 0, "ZERO_PAYMENT");
        // we exclude msg.value from the ratio calculation because the ratio must be calculated based on previous deposits and minted LS tokens
        uint256 toMintLST = (msg.value * lstokenPerUnderlying) / 1 ether;
        require(
            tokenLiquidStaking.totalSupply() + toMintLST <= MAX_LST_SUPPLY,
            "MAX_SUPPLY"
        );
        require(
            tokenLiquidStaking.balanceOf(msg.sender) + toMintLST <=
                MAX_DELEGATION_LST,
            "MAX_DELEG"
        );
        pendingDelegation += int256(msg.value);
        emit DelegatedToPool(msg.sender, msg.value, toMintLST);
        tokenLiquidStaking.mintToAddress(msg.sender, toMintLST);
    }

    /**
    @notice Delegators can schedule to undelegate their funds, i.e. exchange their LS tokens back for GLMR.
    @dev Scheduled delegation requests are place don a FIFO queue and are executed in sequence as funds become available.
    The contract design assumes that ANY reducible balance is immediately available to cover undelegation requests.
    @param _amountLST The amount of LS tokens that this user wants to exchange for the underlying
    */
    function delegatorScheduleUnstakeAndBurnLSTokens(uint256 _amountLST)
        public
        nonReentrant
    {
        require(_amountLST > 0, "ZERO_AMOUNT");
        require(
            tokenLiquidStaking.balanceOf(msg.sender) >= _amountLST,
            "INS_BALANCE"
        );
        uint256 round = staking.round();
        if (!skipRebase && round > lastRoundRebased) {
            _rebase();
        }
        // the exchange rate is booked when the delegator schedules the request
        uint256 toWithdraw = (_amountLST * underlyingPerLSToken) / 1 ether;
        Queue.WhoAmount memory whoAmount = Queue.WhoAmount({
            who: msg.sender,
            amount: toWithdraw,
            round: round
        });
        Queue.pushBack(undelegationQueue, whoAmount);
        pendingSchedulingUndelegation += int256(toWithdraw);
        toClaim += toWithdraw; // toClaim funds will be excluded from "underlying" balance until they are moved out to claimable contract
        delegatorToClaims[msg.sender] += toWithdraw;
        emit ScheduledUndelegateFromPool(msg.sender, toWithdraw, _amountLST);
        tokenLiquidStaking.burnFromAddress(msg.sender, _amountLST);
    }

    //********************* PUBLIC MAINTENANCE METHODS *********************/
    // These methods should be called by the contract manager to keep the contract working efficiently. However, the methods are open for anybody to call.

    /**
    @notice Update the cureency exchange rate to reflect the current staking rewards
    @dev This function should be called once every round (ideally, right after all rewards have been distributed to delegators) to update the exchange rate of LS tokens to the underlying.
    Not calling the function would result to new buyers getting the LS token for slightly cheaper than its actual value, at the expense of current owners.
    */
    function rebase() external {
        _rebase();
    }

    /**
    @dev If an undelegation request takes longer than LIQUIDATION_ROUND_THRESHOLD rounds to be executed,
    OR  if the collator is no longer a registered candidqte, then activate inLiquidation.
    */
    function activateInLiquidation() external virtual {
        bool undelegationThresholdReached = Queue
            .peek(undelegationQueue)
            .round +
            LIQUIDATION_ROUND_THRESHOLD <
            staking.round();
        require(undelegationThresholdReached, "COND_NOT_MET");
        emit InLiquidationActivated();
        inLiquidation = true;
    }

    function withdrawFromLedgerInLiquidation(
        uint256 _ledgerIndex,
        uint256 _amount
    ) external nonReentrant {
        require(inLiquidation, "NO_LIQ");
        emit InLiquidationWithdrawal();
        _withdrawFromLedger(_ledgerIndex, _amount);
    }

    function scheduleRevokeDelegationInLiquidation(
        uint256 _ledgerIndex,
        address _candidate
    ) external nonReentrant {
        require(inLiquidation, "NO_LIQ");
        emit InLiquidationRevoke();
        _scheduleRevokeDelegation(_ledgerIndex, _candidate);
    }

    /**
    @notice Fulfill undelegation requests with available balance
    @dev Anyone can call this method to execute the scheduled undelegation requests
    The method will use any non-reserved funds that are available in reducible balance to pay as many delegators
    as possible, but up to _maxCount (to guard against maxing out on gas). The funds are moved to the claimable
    contract where they can be claimed by delegators. This intermediate transfer step is necessary to avoid griefing.
    */
    function executeUndelegations(uint256 _maxCount) external nonReentrant {
        uint256 amounts;
        for (uint256 i = 0; i < _maxCount; ) {
            if (Queue.isEmpty(undelegationQueue)) {
                break;
            }
            // We exclude pendingDelegation because we have not decided how to allocate it yet
            uint256 availableToClaim = address(this).balance - _toUint256OrZero(pendingDelegation);
            if (Queue.peek(undelegationQueue).amount > availableToClaim) {
                break;
            }
            Queue.WhoAmount memory whoAmount = Queue.popFront(
                undelegationQueue
            );
            address delegator = whoAmount.who;
            uint256 amount = whoAmount.amount;
            delegatorToClaims[delegator] -= amount;
            emit UndelegationExecuted(delegator, amount);
            claimable.depositClaim{value: amount}(delegator);
            amounts += amount;

            unchecked {
                ++i;
            }
        }
        toClaim -= amounts;
    }

    function getLedgersLength() external view returns (uint256) {
        return ledgers.length;
    }

    //********************* MANAGER METHODS  *********************/

    function depositAsBonus() external payable onlyManagerProxy {
        emit DepositedBonus(msg.value);
        pendingDelegation += int256(msg.value);
    }

    function addLedger() external onlyManagerProxy returns (address) {
        return _addLedger();
    }

    function removeLedger(uint256 _ledgerIndex) external onlyManagerProxy {
        require(ledgers.length > 1, "MIN_1_LEDGER");
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address ledger = ledgers[_ledgerIndex];
        require(
            staking.getDelegatorTotalStaked(ledger) == 0,
            "DELEGATION_NOT_ZERO"
        );
        require(address(ledger).balance == 0, "BALANCE_NOT_ZERO");
        uint256 last = ledgers.length - 1;
        if (_ledgerIndex != last) ledgers[_ledgerIndex] = ledgers[last];
        ledgers.pop();
        emit RemovedLedger(ledger);
    }

    function deactivateInLiquidation() external onlyManagerProxy {
        require(
            Queue.peek(undelegationQueue).round + LIQUIDATION_ROUND_THRESHOLD >=
                staking.round(),
            "COND_NOT_MET"
        );
        inLiquidation = false;
        emit InLiquidationDeactivated();
    }

    function withdrawFromLedger(uint256 _ledgerIndex, uint256 _amount)
        external
        onlyManagerProxy
        nonReentrant
    {
        _withdrawFromLedger(_ledgerIndex, _amount);
    }

    function depositToLedger(uint256 _ledgerIndex, uint256 _amount)
        external
        onlyManagerProxy
        nonReentrant
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(payable(_ledger));
        emit DepositedToLedger(_ledger, _amount);
        ledger.deposit{value: _amount}();
    }

    /**
    @dev Convert a part or all of the reducible balance to funds that can be claimed by delegators through pending (queued) undelegation requests
    */
    function makeClaimable(uint256 _amount) external onlyManagerProxy {
        pendingDelegation -= int256(_amount);
        emit MadeClaimable(_amount);
    }

    function netOutPending() external onlyManagerProxy returns (int256) {
        int256 net = pendingDelegation < pendingSchedulingUndelegation
            ? pendingDelegation
            : pendingSchedulingUndelegation;
        pendingDelegation -= net;
        pendingSchedulingUndelegation -= net;
        emit NetOutPending(net);
        return net;
    }

    function netOutPendingAmount(int256 _amount) external onlyManagerProxy {
        pendingDelegation -= _amount;
        pendingSchedulingUndelegation -= _amount;
        emit NetOutPending(_amount);
    }

    function delegate(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        pendingDelegation -= int256(_amount);
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        emit LedgerDelegate(address(ledger), _candidate, _amount);
        ledger.delegate(_candidate, _amount);
    }

    function delegatorBondMore(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        pendingDelegation -= int256(_amount);
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        emit LedgerBondMore(address(ledger), _candidate, _amount);
        ledger.delegatorBondMore(_candidate, _amount);
    }

    function depositAndDelegate(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        pendingDelegation -= int256(_amount);
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(_ledger);
        emit DepositedToLedger(_ledger, _amount);
        emit LedgerDelegate(_ledger, _candidate, _amount);
        ledger.deposit{value: _amount}();
        ledger.delegate(_candidate, _amount);
    }

    function depositAndDelegateWithAutoCompound(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount,
        uint8 _autoCompound
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        pendingDelegation -= int256(_amount);
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(_ledger);
        emit DepositedToLedger(_ledger, _amount);
        emit LedgerDelegateWithAutoCompound(_ledger, _candidate, _amount);
        ledger.deposit{value: _amount}();
        ledger.delegateWithAutoCompound(_candidate, _amount, _autoCompound);
    }

    function depositAndBondMore(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(_ledger);
        emit DepositedToLedger(_ledger, _amount);
        emit LedgerBondMore(_ledger, _candidate, _amount);
        ledger.deposit{value: _amount}();
        ledger.delegatorBondMore(_candidate, _amount);
    }

    function scheduleDelegatorBondLess(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        pendingSchedulingUndelegation -= int256(_amount);
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(payable(_ledger));
        scheduledRequests[_ledger][_candidate] = _amount;
        emit LedgerBondLess(_ledger, _candidate, _amount);
        ledger.scheduleDelegatorBondLess(_candidate, _amount);
    }

    function scheduleRevokeDelegation(uint256 _ledgerIndex, address _candidate)
        external
        onlyManagerProxy
        nonReentrant
    {
        _scheduleRevokeDelegation(_ledgerIndex, _candidate);
    }

    function cancelDelegationRequest(uint256 _ledgerIndex, address _candidate)
        external
        onlyManagerProxy
        nonReentrant
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(_ledger);
        pendingSchedulingUndelegation += int256(
            scheduledRequests[_ledger][_candidate]
        );
        delete scheduledRequests[_ledger][_candidate];
        emit LedgerCancelDelegationRequest(_ledger, _candidate);
        ledger.cancelDelegationRequest(_candidate);
    }

    function setMaxLstSupply(uint256 _maxLST) external onlyManagerProxy {
        require(_maxLST >= tokenLiquidStaking.totalSupply(), "BELOW_SUPPLY");
        MAX_LST_SUPPLY = _maxLST;
        emit MaxLstSupplySet(_maxLST);
    }

    function setMaxDelegationLst(uint256 _maxDelegation)
        external
        onlyManagerProxy
    {
        MAX_DELEGATION_LST = _maxDelegation;
        emit MaxDelegationLstSet(_maxDelegation);
    }

    function setSkipRebase(bool _skipRebase) external onlyManagerProxy {
        skipRebase = _skipRebase;
        emit SkipRebaseSet(_skipRebase);
    }

    function setAutoCompound(
        uint256 _ledgerIndex,
        address _candidate,
        uint8 _value
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(_ledger);
        emit LedgerAutoCompoundSet(_ledger, _candidate, _value);
        ledger.setAutoCompound(_candidate, _value);
    }

    function delegateWithAutoCompound(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount,
        uint8 _autoCompound
    ) external onlyManagerProxy nonReentrant {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        emit LedgerDelegateWithAutoCompound(
            address(ledger),
            _candidate,
            _amount
        );
        ledger.delegateWithAutoCompound(_candidate, _amount, _autoCompound);
    }

    /**
    @dev Anybody can execute undelegations on chain, so this method is mainly for future-proofing in case permissions change
    */
    function executeDelegationRequest(uint256 _ledgerIndex, address _candidate)
        external
        onlyManagerProxy
        nonReentrant
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.executeDelegationRequest(_candidate);
    }

    //********************* CALLABLE BY LEDGERS ONLY  *********************/

    /**
    @dev Used by ledgers to return funds back to the pool. The method confirms it is called by a ledger
    by running _getLedgerIndex which includes a for-loop. Therefore, it's important to limit the size of the ledgers
    array to MAX_LEDGER_COUNT, because a very large length could block moving funds from ledgers back to the pool due to gas limit.
    */
    function depositFromLedger() external payable {
        require(_getLedgerIndex(msg.sender) != N_FOUND, "NOT_LEDGER");
    }

    //********************* INTERNAL POOL METHODS  *********************/

    function _rebase() internal {
        lastRoundRebased = staking.round();
        uint256 underlying = _getUnderlying();
        uint256 lsTokens = tokenLiquidStaking.totalSupply();
        if (underlying == 0 || lsTokens == 0) {
            underlyingPerLSToken = 1 ether;
            lstokenPerUnderlying = 1 ether;
        } else {
            underlyingPerLSToken = (underlying * 1 ether) / lsTokens;
            lstokenPerUnderlying = (lsTokens * 1 ether) / underlying;
        }
        emit Rebase(underlyingPerLSToken, lstokenPerUnderlying);
    }

    function _addLedger() internal returns (address) {
        require(ledgers.length < MAX_LEDGER_COUNT, "MAX_LEDGERS");
        Ledger ledger = new Ledger(PARACHAIN_STAKING, payable(address(this)));
        ledgers.push(payable(address(ledger)));
        emit AddedLedger(address(ledger));
        return address(ledger);
    }

    function _withdrawFromLedger(uint256 _ledgerIndex, uint256 _amount)
        internal
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        require(_ledger.balance >= _amount, "INV_AMOUNT");
        Ledger ledger = Ledger(payable(_ledger));
        emit WithdrawnFromLedger(_ledger, _amount);
        ledger.withdraw(_amount);
    }

    function _scheduleRevokeDelegation(uint256 _ledgerIndex, address _candidate)
        internal
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        uint256 amount = staking.delegationAmount(_ledger, _candidate);
        pendingSchedulingUndelegation -= int256(amount);
        Ledger ledger = Ledger(payable(_ledger));
        scheduledRequests[_ledger][_candidate] = amount;
        emit LedgerScheduledRevoke(_ledger, _candidate);
        ledger.scheduleRevokeDelegation(_candidate);
    }

    /**
    @dev Returns the total underlying (GLMR) this contract owns.
    This equals all reducible funds by this contract and all its ledgers, plus all delegated funds by all its ledgers,
    excluding the amount that is reserved for claiming (LS tokens already burnt for that)
    */
    function _getUnderlying() internal view returns (uint256) {
        uint256 ledgerFunds;
        uint256 ledgersLength = ledgers.length;

        for (uint256 i = 0; i < ledgersLength; ) {
            address ldg = ledgers[i];
            ledgerFunds += ldg.balance;
            ledgerFunds += staking.getDelegatorTotalStaked(ldg);
            unchecked {
                ++i;
            }
        }
        uint256 poolFunds = address(this).balance + ledgerFunds - toClaim;
        // these are funds that delegators have undelegated and waiting to get the underlying; because the corresponding LS tokens have been burnt;
        // pendingSchedulingUndelegation funds is a subset of reducible balance depending on whether the undelegations have been executed or not
        return poolFunds;
    }

    function _getLedgerIndex(address _ledger) internal view returns (uint256) {
        uint256 length = ledgers.length;
        for (uint256 i = 0; i < length; ) {
            if (ledgers[i] == _ledger) {
                return i;
            }
            unchecked {
                ++i;
            }
        }
        return N_FOUND;
    }

    function _isProxy(address _manager) internal view virtual returns (bool) {
        return _manager == MANAGER || proxy.isProxy(MANAGER, _manager, Proxy.ProxyType.Governance, 0);
    }

    function _toUint256OrZero(int256 a) internal pure returns (uint256) {
        if (a < 0) {
            return 0;
        }
        return uint256(a);
    }
}
