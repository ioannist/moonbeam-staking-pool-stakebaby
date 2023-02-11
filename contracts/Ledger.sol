// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import OpenZeppelin Contract
import "./interfaces/StakingInterface.sol";
import "./TokenLiquidStaking.sol";

contract Ledger {

    address payable STAKING_POOL;

    ParachainStaking staking;
   
    modifier onlyStakingPool() {
        require(msg.sender == STAKING_POOL, "NOT_AUTH");
        _;
    }

    function initialize(
        address _parachainStaking,
        address payable _stakingPool
    ) external {
        require(_stakingPool != address(0) && STAKING_POOL == address(0), "ALREADY_INIT");
        STAKING_POOL = _stakingPool;
        staking = ParachainStaking(_parachainStaking);
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
        (bool sent, ) = STAKING_POOL.call{value: _amount}("");
        require(sent, "EXEC_FAIL");
    }

    /**
    @dev Allows the staking pool to deposit funds to the ledger, increasing its reducible balance.
    Although the ledger could be open to receiving funds from other sources (does not break accounting)
    we limit it to receiving only from the stakingPool to allow for easier tracking/auditing of the pool.
    */
    function deposit() external payable onlyStakingPool {}

    receive() external payable {
        revert();
    }

}