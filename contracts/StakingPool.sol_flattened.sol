
// File: contracts/types/Queue.sol



pragma solidity ^0.8.3;

/**
 * @title Queue
 * @author Erick Dagenais (https://github.com/edag94)
 * @dev Implementation of the queue data structure, providing a library with struct definition for queue storage in consuming contracts.
 */
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

    function pushFront(QueueStorage storage queue, WhoAmount calldata data)
        public
    {
        queue._data[--queue._first] = data;
    }

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

    function popBack(QueueStorage storage queue)
        public
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        data = queue._data[queue._last];
        delete queue._data[queue._last--];
    }

    /**
     * @dev Returns the data from the front of the queue, without removing it. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function peek(QueueStorage storage queue)
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
    function peekLast(QueueStorage storage queue)
        public
        view
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        return queue._data[queue._last];
    }
}

// File: contracts/Claimable.sol


pragma solidity ^0.8.3;

// Import OpenZeppelin Contract



contract Claimable {
    address STAKING_POOL;

    // Delegator claimable amounts
    mapping(address => uint256) public claimables;

    event Claimed(address delegator, uint256 amount);
    event ClaimDeposit(address delegator, uint256 amount);

    modifier onlyStakingPool() {
        require(msg.sender == STAKING_POOL, "NOT_POOL");
        _;
    }

    constructor(address _stakingPool) payable {
        STAKING_POOL = _stakingPool;
    }

    function claim(address _delegator) external {
        uint256 amount = claimables[_delegator];
        require(amount > 0, "ZERO_CLAIM");
        claimables[_delegator] = 0;
        emit Claimed(_delegator, amount);
        (bool sent, ) = _delegator.call{value: amount}("");
        require(sent, "TRANSFER_FAIL");
    }

    function depositClaim(address _delegator) external payable onlyStakingPool {
        emit ClaimDeposit(_delegator, msg.value);
        claimables[_delegator] += msg.value;
    }
}

// File: contracts/Ledger.sol


pragma solidity ^0.8.3;

// Import OpenZeppelin Contract




contract Ledger {

    address payable STAKING_POOL;

    ParachainStaking staking;
    StakingPool stakingPool;
   
    modifier onlyStakingPool() {
        require(msg.sender == STAKING_POOL, "NOT_POOL");
        _;
    }

    constructor(
        address _parachainStaking,
        address payable _stakingPool
    ) {
        STAKING_POOL = _stakingPool;
        staking = ParachainStaking(_parachainStaking);
        stakingPool = StakingPool(STAKING_POOL);
    }

    function getBalance() external view returns(uint256) {
        return address(this).balance;
    }

    function getDelegatorTotalStaked() external view returns(uint256) {
        return staking.getDelegatorTotalStaked(address(this));
    }

    function getDelegationAmount(address _candidate) external view returns(uint256) {
        return staking.delegationAmount(address(this), _candidate);
    }

    function delegate(address _candidate, uint256 _delegation) external onlyStakingPool {
        staking.delegate(
                _candidate,
                _delegation,
                staking.candidateDelegationCount(_candidate),
                staking.delegatorDelegationCount(address(this))
        );
    }

    function delegatorBondMore(address _candidate, uint256 _delegation)
        external onlyStakingPool
    {
        staking.delegatorBondMore(_candidate, _delegation);
    }


    function scheduleDelegatorBondLess(address _candidate, uint256 _toUndelegate)
        external onlyStakingPool
    {
        staking.scheduleDelegatorBondLess(_candidate, _toUndelegate);
    }
    function scheduleRevokeDelegation(address _candidate) external onlyStakingPool {
        // we cannot revoke members that have made the minimum deposits
        staking.scheduleRevokeDelegation(_candidate);
    }

    
    function cancelDelegationRequest(address _candidate) external onlyStakingPool {
        staking.cancelDelegationRequest(_candidate);
    }

    function setAutoCompound(
        address _candidate,
        uint8 _value
    ) external onlyStakingPool {
        uint32 candidateAutoCompoundingDelegationCount = staking.candidateAutoCompoundingDelegationCount(_candidate);
        staking.setAutoCompound(
            _candidate,
            _value,
            candidateAutoCompoundingDelegationCount,
            staking.delegatorDelegationCount(address(this))
        );
    }

    function delegateWithAutoCompound(
        address _candidate,
        uint256 _amount,
        uint8 _autoCompound
    ) external onlyStakingPool {
        staking.delegateWithAutoCompound(
            _candidate,
            _amount,
            _autoCompound,
            staking.candidateDelegationCount(_candidate),
            staking.candidateAutoCompoundingDelegationCount(_candidate),
            staking.delegatorDelegationCount(address(this))
        );
    }

    function executeDelegationRequest(address _candidate) external onlyStakingPool {
        staking.executeDelegationRequest(address(this), _candidate);
    }

    function withdraw(uint256 _amount) external onlyStakingPool {
        stakingPool.depositFromLedger{value: _amount}();
    }

    /**
    @dev Allows the staking pool to deposit funds to the ledger, increasing its reducible balance.
    Although the ledger could be open to receiving funds from other sources (does not break accounting)
    we limit it to receiving only from the stakingPool to allow for easier tracking/auditing of the pool.
    */
    function deposit() external payable onlyStakingPool {}

}
// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}



// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

// File: @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol


// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.0;


/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// File: @openzeppelin/contracts/token/ERC20/ERC20.sol


// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;




/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

// File: contracts/TokenLiquidStaking.sol


pragma solidity ^0.8.3;

// Import OpenZeppelin Contract


// This ERC-20 contract mints the specified amount of tokens to the contract creator.
contract TokenLiquidStaking is ERC20  {

    address payable STAKING_POOL;

    constructor(uint256 initialSupply, address payable _stakingPool) ERC20("MamaGLMR", "mamaGLMR") 
    {
        STAKING_POOL = _stakingPool;
        _mint(msg.sender, initialSupply);
    }

    // Allows function calls only from StakingPool
    modifier onlyStakingPool() {
        require(msg.sender == STAKING_POOL, "NOT_POOL");
        _;
    }

    function mintToAddress(address _to, uint256 _amount) public onlyStakingPool {
        _mint(_to, _amount);
    }

    function burnFromAddress(address _from, uint256 _amount) public onlyStakingPool {
        _burn(_from, _amount);
    }
}

// File: contracts/interfaces/Proxy.sol


pragma solidity >=0.8.3;

/// @dev The Proxy contract's address.
address constant PROXY_ADDRESS = 0x000000000000000000000000000000000000080b;

/// @dev The Proxy contract's instance.
Proxy constant PROXY_CONTRACT = Proxy(PROXY_ADDRESS);

/// @author The Moonbeam Team
/// @title Pallet Proxy Interface
/// @title The interface through which solidity contracts will interact with the Proxy pallet
/// @custom:address 0x000000000000000000000000000000000000080b
interface Proxy {
    /// @dev Defines the proxy permission types.
    /// The values start at `0` (most permissive) and are represented as `uint8`
    enum ProxyType {
        Any,
        NonTransfer,
        Governance,
        Staking,
        CancelProxy,
        Balances,
        AuthorMapping,
        IdentityJudgement
    }

    /// @dev Register a proxy account for the sender that is able to make calls on its behalf
    /// @custom:selector 74a34dd3
    /// @param delegate The account that the caller would like to make a proxy
    /// @param proxyType The permissions allowed for this proxy account
    /// @param delay The announcement period required of the initial proxy, will generally be zero
    function addProxy(
        address delegate,
        ProxyType proxyType,
        uint32 delay
    ) external;

    /// @dev Register a proxy account for the sender that is able to make calls on its behalf
    /// @custom:selector fef3f708
    /// @param delegate The account that the caller would like to remove as a proxy
    /// @param proxyType The permissions currently enabled for the removed proxy account
    /// @param delay The announcement period required of the initial proxy, will generally be zero
    function removeProxy(
        address delegate,
        ProxyType proxyType,
        uint32 delay
    ) external;

    /// @dev Unregister all proxy accounts for the sender
    /// @custom:selector 14a5b5fa
    function removeProxies() external;

    /// @dev Checks if the caller has an account proxied with a given proxy type
    /// @custom:selector e26d38ed
    /// @param real The real account that maybe has a proxy
    /// @param delegate The account that the caller has maybe proxied
    /// @param proxyType The permissions allowed for the proxy
    /// @param delay The announcement period required of the initial proxy, will generally be zero
    /// @return exists True if a proxy exists, False otherwise
    function isProxy(
        address real,
        address delegate,
        ProxyType proxyType,
        uint32 delay
    ) external view returns (bool exists);
}
// File: contracts/interfaces/StakingInterface.sol


pragma solidity >=0.8.3;

/// @dev The ParachainStaking contract's address.
address constant PARACHAIN_STAKING_ADDRESS = 0x0000000000000000000000000000000000000800;

/// @dev The ParachainStaking contract's instance.
ParachainStaking constant PARACHAIN_STAKING_CONTRACT = ParachainStaking(
    PARACHAIN_STAKING_ADDRESS
);

/// @author The Moonbeam Team
/// @title Pallet Parachain Staking Interface
/// @dev The interface through which solidity contracts will interact with Parachain Staking
/// We follow this same interface including four-byte function selectors, in the precompile that
/// wraps the pallet
/// @custom:address 0x0000000000000000000000000000000000000800
interface ParachainStaking {
    /// @dev Check whether the specified address is currently a staking delegator
    /// @custom:selector fd8ab482
    /// @param delegator the address that we want to confirm is a delegator
    /// @return A boolean confirming whether the address is a delegator
    function isDelegator(address delegator) external view returns (bool);

    /// @dev Check whether the specified address is currently a collator candidate
    /// @custom:selector d51b9e93
    /// @param candidate the address that we want to confirm is a collator andidate
    /// @return A boolean confirming whether the address is a collator candidate
    function isCandidate(address candidate) external view returns (bool);

    /// @dev Check whether the specifies address is currently a part of the active set
    /// @custom:selector 740d7d2a
    /// @param candidate the address that we want to confirm is a part of the active set
    /// @return A boolean confirming whether the address is a part of the active set
    function isSelectedCandidate(address candidate)
        external
        view
        returns (bool);

    /// @dev Total points awarded to all collators in a particular round
    /// @custom:selector 9799b4e7
    /// @param round the round for which we are querying the points total
    /// @return The total points awarded to all collators in the round
    function points(uint256 round) external view returns (uint256);

    /// @dev The amount delegated in support of the candidate by the delegator
    /// @custom:selector a73e51bc
    /// @param delegator Who made this delegation
    /// @param candidate The candidate for which the delegation is in support of
    /// @return The amount of the delegation in support of the candidate by the delegator
    function delegationAmount(address delegator, address candidate)
        external
        view
        returns (uint256);

    /// @dev Whether the delegation is in the top delegations
    /// @custom:selector 91cc8657
    /// @param delegator Who made this delegation
    /// @param candidate The candidate for which the delegation is in support of
    /// @return If delegation is in top delegations (is counted)
    function isInTopDelegations(address delegator, address candidate)
        external
        view
        returns (bool);

    /// @dev Get the minimum delegation amount
    /// @custom:selector 02985992
    /// @return The minimum delegation amount
    function minDelegation() external view returns (uint256);

    /// @dev Get the CandidateCount weight hint
    /// @custom:selector a9a981a3
    /// @return The CandidateCount weight hint
    function candidateCount() external view returns (uint256);

    /// @dev Get the current round number
    /// @custom:selector 146ca531
    /// @return The current round number
    function round() external view returns (uint256);

    /// @dev Get the CandidateDelegationCount weight hint
    /// @custom:selector 2ec087eb
    /// @param candidate The address for which we are querying the nomination count
    /// @return The number of nominations backing the collator
    function candidateDelegationCount(address candidate)
        external
        view
        returns (uint32);

    /// @dev Get the CandidateAutoCompoundingDelegationCount weight hint
    /// @custom:selector 905f0806
    /// @param candidate The address for which we are querying the auto compounding
    ///     delegation count
    /// @return The number of auto compounding delegations
    function candidateAutoCompoundingDelegationCount(address candidate)
        external
        view
        returns (uint32);

    /// @dev Get the DelegatorDelegationCount weight hint
    /// @custom:selector 067ec822
    /// @param delegator The address for which we are querying the delegation count
    /// @return The number of delegations made by the delegator
    function delegatorDelegationCount(address delegator)
        external
        view
        returns (uint256);

    /// @dev Get the selected candidates for the current round
    /// @custom:selector bcf868a6
    /// @return The selected candidate accounts
    function selectedCandidates() external view returns (address[] memory);

    /// @dev Whether there exists a pending request for a delegation made by a delegator
    /// @custom:selector 3b16def8
    /// @param delegator the delegator that made the delegation
    /// @param candidate the candidate for which the delegation was made
    /// @return Whether a pending request exists for such delegation
    function delegationRequestIsPending(address delegator, address candidate)
        external
        view
        returns (bool);

    /// @dev Whether there exists a pending exit for candidate
    /// @custom:selector 43443682
    /// @param candidate the candidate for which the exit request was made
    /// @return Whether a pending request exists for such delegation
    function candidateExitIsPending(address candidate)
        external
        view
        returns (bool);

    /// @dev Whether there exists a pending bond less request made by a candidate
    /// @custom:selector d0deec11
    /// @param candidate the candidate which made the request
    /// @return Whether a pending bond less request was made by the candidate
    function candidateRequestIsPending(address candidate)
        external
        view
        returns (bool);

    /// @dev Returns the percent value of auto-compound set for a delegation
    /// @custom:selector b4d4c7fd
    /// @param delegator the delegator that made the delegation
    /// @param candidate the candidate for which the delegation was made
    /// @return Percent of rewarded amount that is auto-compounded on each payout
    function delegationAutoCompound(address delegator, address candidate)
        external
        view
        returns (uint8);

    /// @dev Join the set of collator candidates
    /// @custom:selector 1f2f83ad
    /// @param amount The amount self-bonded by the caller to become a collator candidate
    /// @param candidateCount The number of candidates in the CandidatePool
    function joinCandidates(uint256 amount, uint256 candidateCount) external;

    /// @dev Request to leave the set of collator candidates
    /// @custom:selector b1a3c1b7
    /// @param candidateCount The number of candidates in the CandidatePool
    function scheduleLeaveCandidates(uint256 candidateCount) external;

    /// @dev Execute due request to leave the set of collator candidates
    /// @custom:selector 3867f308
    /// @param candidate The candidate address for which the pending exit request will be executed
    /// @param candidateDelegationCount The number of delegations for the candidate to be revoked
    function executeLeaveCandidates(
        address candidate,
        uint256 candidateDelegationCount
    ) external;

    /// @dev Cancel request to leave the set of collator candidates
    /// @custom:selector 9c76ebb4
    /// @param candidateCount The number of candidates in the CandidatePool
    function cancelLeaveCandidates(uint256 candidateCount) external;

    /// @dev Temporarily leave the set of collator candidates without unbonding
    /// @custom:selector a6485ccd
    function goOffline() external;

    /// @dev Rejoin the set of collator candidates if previously had called `goOffline`
    /// @custom:selector 6e5b676b
    function goOnline() external;

    /// @dev Request to bond more for collator candidates
    /// @custom:selector a52c8643
    /// @param more The additional amount self-bonded
    function candidateBondMore(uint256 more) external;

    /// @dev Request to bond less for collator candidates
    /// @custom:selector 60744ae0
    /// @param less The amount to be subtracted from self-bond and unreserved
    function scheduleCandidateBondLess(uint256 less) external;

    /// @dev Execute pending candidate bond request
    /// @custom:selector 2e290290
    /// @param candidate The address for the candidate for which the request will be executed
    function executeCandidateBondLess(address candidate) external;

    /// @dev Cancel pending candidate bond request
    /// @custom:selector b5ad5f07
    function cancelCandidateBondLess() external;

    /// @dev Make a delegation in support of a collator candidate
    /// @custom:selector 829f5ee3
    /// @param candidate The address of the supported collator candidate
    /// @param amount The amount bonded in support of the collator candidate
    /// @param candidateDelegationCount The number of delegations in support of the candidate
    /// @param delegatorDelegationCount The number of existing delegations by the caller
    function delegate(
        address candidate,
        uint256 amount,
        uint256 candidateDelegationCount,
        uint256 delegatorDelegationCount
    ) external;

    /// @dev Make a delegation in support of a collator candidate
    /// @custom:selector 4b8bc9bf
    /// @param candidate The address of the supported collator candidate
    /// @param amount The amount bonded in support of the collator candidate
    /// @param autoCompound The percent of reward that should be auto-compounded
    /// @param candidateDelegationCount The number of delegations in support of the candidate
    /// @param candidateAutoCompoundingDelegationCount The number of auto-compounding delegations
    /// in support of the candidate
    /// @param delegatorDelegationCount The number of existing delegations by the caller
    function delegateWithAutoCompound(
        address candidate,
        uint256 amount,
        uint8 autoCompound,
        uint256 candidateDelegationCount,
        uint256 candidateAutoCompoundingDelegationCount,
        uint256 delegatorDelegationCount
    ) external;

    /// @notice DEPRECATED use batch util with scheduleRevokeDelegation for all delegations
    /// @dev Request to leave the set of delegators
    /// @custom:selector f939dadb
    function scheduleLeaveDelegators() external;

    /// @notice DEPRECATED use batch util with executeDelegationRequest for all delegations
    /// @dev Execute request to leave the set of delegators and revoke all delegations
    /// @custom:selector fb1e2bf9
    /// @param delegator The leaving delegator
    /// @param delegatorDelegationCount The number of active delegations to be revoked by delegator
    function executeLeaveDelegators(
        address delegator,
        uint256 delegatorDelegationCount
    ) external;

    /// @notice DEPRECATED use batch util with cancelDelegationRequest for all delegations
    /// @dev Cancel request to leave the set of delegators
    /// @custom:selector f7421284
    function cancelLeaveDelegators() external;

    /// @dev Request to revoke an existing delegation
    /// @custom:selector 1a1c740c
    /// @param candidate The address of the collator candidate which will no longer be supported
    function scheduleRevokeDelegation(address candidate) external;

    /// @dev Bond more for delegators with respect to a specific collator candidate
    /// @custom:selector 0465135b
    /// @param candidate The address of the collator candidate for which delegation shall increase
    /// @param more The amount by which the delegation is increased
    function delegatorBondMore(address candidate, uint256 more) external;

    /// @dev Request to bond less for delegators with respect to a specific collator candidate
    /// @custom:selector c172fd2b
    /// @param candidate The address of the collator candidate for which delegation shall decrease
    /// @param less The amount by which the delegation is decreased (upon execution)
    function scheduleDelegatorBondLess(address candidate, uint256 less)
        external;

    /// @dev Execute pending delegation request (if exists && is due)
    /// @custom:selector e98c8abe
    /// @param delegator The address of the delegator
    /// @param candidate The address of the candidate
    function executeDelegationRequest(address delegator, address candidate)
        external;

    /// @dev Cancel pending delegation request (already made in support of input by caller)
    /// @custom:selector c90eee83
    /// @param candidate The address of the candidate  
    function cancelDelegationRequest(address candidate) external;

    /// @dev Sets an auto-compound value for a delegation
    /// @custom:selector faa1786f
    /// @param candidate The address of the supported collator candidate
    /// @param value The percent of reward that should be auto-compounded
    /// @param candidateAutoCompoundingDelegationCount The number of auto-compounding delegations
    /// in support of the candidate
    /// @param delegatorDelegationCount The number of existing delegations by the caller
    function setAutoCompound(
        address candidate,
        uint8 value,
        uint256 candidateAutoCompoundingDelegationCount,
        uint256 delegatorDelegationCount
    ) external;

    /// @dev Fetch the total staked amount of a delegator, regardless of the
    /// candidate.
    /// @custom:selector e6861713
    /// @param delegator Address of the delegator.
    /// @return Total amount of stake.
    function getDelegatorTotalStaked(address delegator)
        external
        view
        returns (uint256);

    /// @dev Fetch the total staked towards a candidate.
    /// @custom:selector bc5a1043
    /// @param candidate Address of the candidate.
    /// @return Total amount of stake.
    function getCandidateTotalCounted(address candidate)
        external
        view
        returns (uint256);
}
// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File: contracts/StakingPool.sol


pragma solidity ^0.8.3;

// Import OpenZeppelin Contract








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
