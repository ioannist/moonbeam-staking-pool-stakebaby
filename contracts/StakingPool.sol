// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import OpenZeppelin Contract
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ParachainStaking} from "./interfaces/StakingInterface.sol";
import {Proxy} from "./interfaces/Proxy.sol";
import {TokenLiquidStaking} from "./TokenLiquidStaking.sol";
import {Ledger} from "./Ledger.sol";
import {Claimable} from "./Claimable.sol";

contract StakingPool is ReentrancyGuard {

    //Contract accounts
    address TOKEN_LIQUID_STAKING;
    address LEDGER;
    address payable CLAIMABLE;
    // User accounts
    address COLLATOR;
    address COMPLIANCE_OFFICER;

    // If a pending undelegation request takes more than this rounds to be served, then inLiquidation -> true
    uint256 public constant LIQUIDATION_ROUND_THRESHOLD = 12 * 30;
    // The pool must maintain at least this % of staked funds, staked to COLLATOR
    uint256 public constant MIN_PER_STAKED_TO_COLLATOR = 50;

    ParachainStaking staking;
    Proxy proxy;
    TokenLiquidStaking tokenLiquidStaking;
    Claimable claimable;

    bool public inLiquidation;
    bool public uncompliance;

    // Ledgers (contracts that stake on behalf of this contract)
    address payable[] public ledgers;

    // Last round that we called rebase on
    uint256 public lastRoundRebased;

    // Current exchange rate
    uint256 public underlyingPerLSToken = 1 ether; // 1:1 starting ratio
    uint256 public lstokenPerUnderlying = 1 ether; // 1:1 starting ratio

    // Current total claimed through delegator initiated undelegations that burnt the LS token leg.
    // Buffered incoming delegation requests
    uint256 public pendingDelegation;
    // Buffered incoming undelegation requests
    uint256 public pendingSchedulingUndelegation;
    // toClaim is the amount of underlying that is excluded from the pool, and has its corresponding LS tokens burnt
    // This amount is to be transfered to the claimable contract as soon as it is available
    uint256 public toClaim;

    // Pending undelegation requests (smart contract),
    // who: delegator
    // amount: delegation (underlying)
    Queue.QueueStorage public undelegationQueue;

    modifier onlyCollatorProxy() {
        require(_isProxy(msg.sender), "NOT_AUTH");
        _;
    }

    modifier onlyComplianceOfficer() {
        require(msg.sender == COMPLIANCE_OFFICER, "NOT_AUTH");
        _;
    }

    function initialize(
        address _collator,
        address _parachainStaking,
        address _tokenLiquidStaking,
        address payable _claimable
    ) external payable {
        require(
            _tokenLiquidStaking != address(0) &&
                TOKEN_LIQUID_STAKING == address(0),
            "ALREADY_INIT"
        );
        COLLATOR = _collator;
        TOKEN_LIQUID_STAKING = _tokenLiquidStaking;
        CLAIMABLE = _claimable;
        tokenLiquidStaking = TokenLiquidStaking(TOKEN_LIQUID_STAKING);
        staking = ParachainStaking(_parachainStaking);
        claimable = Claimable(CLAIMABLE);
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
    function delegatorStakeAndReceiveLSTokens() public payable {
        require(msg.value > 0, "ZERO_PAYMENT");
        // we exclude msg.value from the ratio calculation because the ratio must be calculated based on previous deposits and minted LS tokens
        uint256 toMintLST = (msg.value * lstokenPerUnderlying) / 1 ether;
        pendingDelegation += msg.value;
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
    {
        require(_amountLST > 0, "ZERO_AMOUNT");
        require(
            tokenLiquidStaking.balanceOf(msg.sender) >= _amountLST,
            "INS_BALANCE"
        );
        if (staking.round() > lastRoundRebased) {
            _rebase();
        }
        // the exchange rate is booked when the delegator schedules the request
        uint256 toWithdraw = (_amountLST * underlyingPerLSToken) / 1 ether;
        Queue.WhoAmount memory whoAmount = Queue.WhoAmount({
            who: msg.sender,
            amount: toWithdraw,
            round: staking.round()
        });
        Queue.pushBack(undelegationQueue, whoAmount);
        pendingSchedulingUndelegation += toWithdraw;
        toClaim += toWithdraw;
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

    function checkMinStakedCompliance() external {
        uint256 staked;
        uint256 collatorStaked;
        uint256 ledgersLength = ledgers.length;

        for (uint256 i = 0; i < ledgersLength; ) {
            address ldg = ledgers[i];
            staked += staking.getDelegatorTotalStaked(ldg);
            collatorStaked += staking.delegationAmount(ldg, COLLATOR);
            unchecked {
                ++i;
            }
        }
        // If pool is staking less then MIN_PER_STAKED_TO_COLLATOR to COLLATOR, then it is not in compliance
        uncompliance =
            (100 * collatorStaked) / staked < MIN_PER_STAKED_TO_COLLATOR;
    }

    /**
    @dev If an undelegation request takes longer than LIQUIDATION_ROUND_THRESHOLD rounds to be executed,
    OR  if the collator is no longer a registered candidqte, then activate inLiquidation.
    */
    function activateInLiquidation() external {
        bool undelegationThresholdReached = Queue
            .peekFront(undelegationQueue)
            .round +
            LIQUIDATION_ROUND_THRESHOLD <
            staking.round();
        bool isNotCandidate = !staking.isCandidate(COLLATOR);
        require(undelegationThresholdReached || isNotCandidate, "COND_NOT_MET");
        inLiquidation = true;
    }

    function withdrawFromLedgerInLiquidation(
        uint256 _ledgerIndex,
        uint256 _amount
    ) external {
        require(inLiquidation, "NO_LIQ");
        _withdrawFromLedger(_ledgerIndex, _amount);
    }

    function scheduleRevokeDelegationInLiquidation(uint256 _ledgerIndex, address _candidate)
        external
    {
        require(inLiquidation, "NO_LIQ");
        _scheduleRevokeDelegation(_ledgerIndex, _candidate);
    }

    function scheduleRevokeDelegationInUncompliance(uint256 _ledgerIndex, address _candidate)
        external onlyComplianceOfficer
    {
        require(uncompliance, "IN_COMPLIANCE");
        _scheduleRevokeDelegation(_ledgerIndex, _candidate);
    }

    /**
    @notice Fulfill undelegation requests with available balance
    @dev Anyone can call this method to execute the scheduled undelegation requests
    The method will use any non-reserved funds that are available in reducible balance to pay as many delegators
    as possible, but up to _maxCount (to guard against maxing out on gas).
    */
    function executeUndelegations(uint256 _maxCount) external nonReentrant {
        uint256 amounts;
        for (uint256 i = 0; i <= _maxCount; i++) {
            // We exclude pendingDelegation because we have not decided how to allocate it yet
            uint256 availableToClaim = address(this).balance -
                pendingDelegation; // guaranteed non-zero because pendingDelegation is a subgroup of reducible balance
            if (Queue.peekFront(undelegationQueue).amount > availableToClaim) {
                break;
            }
            Queue.WhoAmount memory whoAmount = Queue.popFront(
                undelegationQueue
            );
            address delegator = whoAmount.who;
            uint256 amount = whoAmount.amount;
            claimable.depositClaim{value: amount}(delegator);
            amounts += amount;
        }
        toClaim -= amounts;
    }

    function getLedgersLength() external view returns (uint256) {
        return ledgers.length;
    }

    //********************* MANAGER METHODS  *********************/

    function addLedger() external onlyCollatorProxy returns (address) {
        return _addLedger();
    }

    function removeLedger(uint256 _ledgerIndex) external onlyCollatorProxy {
        require(ledgers.length > 1, "MIN_1_LEDGER");
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address ledger = ledgers[_ledgerIndex];
        require(
            staking.delegationAmount(ledger, COLLATOR) == 0,
            "DELEGATION_NOT_ZERO"
        );
        require(address(ledger).balance == 0, "BALANCE_NOT_ZERO");
        uint256 last = ledgers.length - 1;
        if (_ledgerIndex != last) ledgers[_ledgerIndex] = ledgers[last];
        ledgers.pop();
    }

    function deactivateInLiquidation() external onlyCollatorProxy {
        require(
            Queue.peekFront(undelegationQueue).round +
                LIQUIDATION_ROUND_THRESHOLD >=
                staking.round(),
            "COND_NOT_MET"
        );
        inLiquidation = false;
    }

    function withdrawFromLedger(uint256 _ledgerIndex, uint256 _amount)
        external
        onlyCollatorProxy
    {
        _withdrawFromLedger(_ledgerIndex, _amount);
    }

    function depositToLedger(uint256 _ledgerIndex, uint256 _amount)
        external
        onlyCollatorProxy
    {
        require(address(this).balance >= _amount, "INV_AMOUNT");
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(_ledger);
        ledger.deposit{value: _amount}();
    }

    /**
    @dev Convert a part or all of the reducible balance to funds that can be claimed by delegators through undelegation requests
    */
    function makeClaimable(uint256 _amount) external onlyCollatorProxy {
        require(_amount <= pendingDelegation && _amount > 0, "INV_AMOUNT");
        pendingDelegation -= _amount;
    }

    function netOutPending() external onlyCollatorProxy returns (uint256) {
        uint256 net = pendingDelegation < pendingSchedulingUndelegation
            ? pendingDelegation
            : pendingSchedulingUndelegation;
        pendingDelegation -= net;
        pendingSchedulingUndelegation -= net;
        return net;
    }

    function netOutPendingAmount(uint256 _amount) external onlyCollatorProxy {
        require(_amount <= pendingSchedulingUndelegation, "INV_UNDEL_AMOUNT");
        require(_amount <= pendingDelegation, "INV_DEL_AMOUNT");
        pendingDelegation -= _amount;
        pendingSchedulingUndelegation -= _amount;
    }

    function delegate(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyCollatorProxy {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        require(_amount <= pendingDelegation, "INV_AMOUNT");
        pendingDelegation -= _amount;
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.delegate(_candidate, _amount);
    }

    function delegatorBondMore(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyCollatorProxy {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        require(_amount <= pendingDelegation, "INV_AMOUNT");
        pendingDelegation -= _amount;
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.delegatorBondMore(_candidate, _amount);
    }

    function depositAndDelegate(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyCollatorProxy {
        _depositAndDelegate(_ledgerIndex, _candidate, _amount);
    }

    function depositAndDelegateWithAutoCompound(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount,
        uint8 _autoCompound
    ) external onlyCollatorProxy {
        _depositAndDelegateWithAutoCompound(_ledgerIndex, _candidate, _amount, _autoCompound);
    }

    function depositAndBondMore(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyCollatorProxy {
        _depositAndBondMore(_ledgerIndex, _candidate, _amount);
    }

    function scheduleDelegatorBondLess(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) external onlyCollatorProxy {
        _scheduleDelegatorBondLess(_ledgerIndex, _candidate, _amount);
    }

    function scheduleRevokeDelegation(uint256 _ledgerIndex, address _candidate)
        external
        onlyCollatorProxy
    {
        _scheduleRevokeDelegation(_ledgerIndex, _candidate);
    }

    function cancelDelegationRequest(uint256 _ledgerIndex, address _candidate)
        external
        onlyCollatorProxy
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        require(!uncompliance, "IN_UNCOMPLIANCE");
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.cancelDelegationRequest(_candidate);
    }

    function setComplianceOfficer(address _officer) external onlyCollatorProxy {
        require(COMPLIANCE_OFFICER == address(0), "ALREADY_INIT");
        require(_officer != address(0), "INV_ADDRESS");
        COMPLIANCE_OFFICER = _officer;
    }

    function setAutoCompound(
        uint256 _ledgerIndex,
        address _candidate,
        uint8 _value
    ) external onlyCollatorProxy {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.setAutoCompound(_candidate, _value);
    }

    function delegateWithAutoCompound(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount,
        uint8 _autoCompound
    ) external onlyCollatorProxy {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.delegateWithAutoCompound(_candidate, _amount, _autoCompound);
    }


    /**
    @dev Anybody can execute undelegations on chain, so this method is mainly for future-proofing in case permissions change
    */
    function executeDelegationRequest(uint256 _ledgerIndex, address _candidate)
        external
        onlyCollatorProxy
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.executeDelegationRequest(_candidate);
    }

    function executeMatureUndelegationRequests(address _candidate)
        external
        onlyCollatorProxy
    {
        for (uint256 i = 0; i < ledgers.length; i++) {
            address _ledger = ledgers[i];
            // If there is no undelegation request, skip
            if (!staking.delegationRequestIsPending(_ledger, _candidate)) {
                continue;
            }
            try
                staking.executeDelegationRequest(_ledger, _candidate)
            {} catch {}
        }
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
    }

    function _addLedger() internal returns (address) {
        Ledger ledger = new Ledger();
        ledgers.push(payable(address(ledger)));
        return address(ledger);
    }

    function _withdrawFromLedger(uint256 _ledgerIndex, uint256 _amount)
        internal
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        require(address(_ledger).balance >= _amount, "INV_AMOUNT");
        Ledger ledger = Ledger(_ledger);
        ledger.withdraw(_amount);
    }

    function _depositAndDelegate(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) internal {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        require(_amount <= pendingDelegation, "INV_AMOUNT");
        pendingDelegation -= _amount;
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.deposit{value: _amount}();
        ledger.delegate(_candidate, _amount);
    }

    function _depositAndDelegateWithAutoCompound(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount,
        uint8 _autoCompound
    ) internal {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        require(_amount <= pendingDelegation, "INV_AMOUNT");
        pendingDelegation -= _amount;
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.deposit{value: _amount}();
        ledger.delegateWithAutoCompound(_candidate, _amount, _autoCompound);
    }

    function _depositAndBondMore(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) private {
        require(address(this).balance >= _amount, "INV_AMOUNT");
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        Ledger ledger = Ledger(ledgers[_ledgerIndex]);
        ledger.deposit{value: _amount}();
        ledger.delegatorBondMore(_candidate, _amount);
    }

    function _scheduleDelegatorBondLess(
        uint256 _ledgerIndex,
        address _candidate,
        uint256 _amount
    ) internal {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        require(_amount <= pendingSchedulingUndelegation, "INV_AMOUNT");
        pendingSchedulingUndelegation -= _amount;
        address _ledger = ledgers[_ledgerIndex];
        Ledger ledger = Ledger(_ledger);
        ledger.scheduleDelegatorBondLess(_candidate, _amount);
    }

    function _scheduleRevokeDelegation(uint256 _ledgerIndex, address _candidate)
        internal
    {
        require(_ledgerIndex < ledgers.length, "INV_INDEX");
        address _ledger = ledgers[_ledgerIndex];
        uint256 amount = staking.delegationAmount(_ledger, COLLATOR);
        require(amount <= pendingSchedulingUndelegation, "INV_AMOUNT");
        pendingSchedulingUndelegation -= amount;
        Ledger ledger = Ledger(_ledger);
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
            ledgerFunds += address(ldg).balance;
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
    
    function _isProxy(address _manager) internal view virtual returns(bool) {
        return proxy.isProxy(
            COLLATOR,
            _manager,
            Proxy.ProxyType.Governance,
            0
        );
    }
}

//********************* QUEUE *********************/

library Queue {
    struct WhoAmount {
        address who;
        uint256 amount;
        uint256 round;
    }

    struct QueueStorage {
        mapping(int256 => WhoAmount) _data;
        int256 _first;
        int256 _last;
    }

    modifier isNotEmpty(QueueStorage storage queue) {
        require(!isEmpty(queue), "Queue is empty.");
        _;
    }

    /**
     * @dev Sets the queue's initial state, with a queue size of 0.
     * @param queue QueueStorage struct from contract.
     */
    function initialize(QueueStorage storage queue) external {
        queue._first = 1;
        queue._last = 0;
    }

    function reset(QueueStorage storage queue) public {
        for (int256 i = queue._first; i <= queue._last; i++) {
            delete queue._data[i];
        }
        queue._first = 1;
        queue._last = 0;
    }

    /**
     * @dev Gets the number of elements in the queue. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function length(QueueStorage storage queue) public view returns (uint256) {
        if (queue._last < queue._first) {
            return 0;
        }
        return uint256(queue._last - queue._first + 1); // always positive
    }

    /**
     * @dev Returns if queue is empty. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function isEmpty(QueueStorage storage queue) public view returns (bool) {
        return length(queue) == 0;
    }

    /**
     * @dev Adds an element to the back of the queue. O(1)
     * @param queue QueueStorage struct from contract.
     * @param data The added element's data.
     */
    function pushBack(QueueStorage storage queue, WhoAmount calldata data)
        public
    {
        queue._data[++queue._last] = data;
    }

    /*function pushFront(QueueStorage storage queue, WhoAmount calldata data)
        public
    {
        queue._data[--queue._first] = data;
    }*/

    /**
     * @dev Removes an element from the front of the queue and returns it. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function popFront(QueueStorage storage queue)
        public
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        data = queue._data[queue._first];
        delete queue._data[queue._first++];
    }

    /*function popBack(QueueStorage storage queue)
        public
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        data = queue._data[queue._last];
        delete queue._data[queue._last--];
    }*/

    /**
     * @dev Returns the data from the front of the queue, without removing it. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function peekFront(QueueStorage storage queue)
        public
        view
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        return queue._data[queue._first];
    }

    /**
     * @dev Returns the data from the back of the queue. O(1)
     * @param queue QueueStorage struct from contract.
     */
    /*function peekBack(QueueStorage storage queue)
        public
        view
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        return queue._data[queue._last];
    }*/
}
