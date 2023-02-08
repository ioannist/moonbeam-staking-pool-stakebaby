// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import OpenZeppelin Contract
import "./interfaces/StakingInterface.sol";
import "./TokenLiquidStaking.sol";

contract Ledger {

    address payable STAKING_POOL;
    address COLLATOR;

    ParachainStaking staking;
   
    modifier onlyStakingPool() {
        require(msg.sender == STAKING_POOL, "NOT_AUTH");
        _;
    }

    function initialize(
        address _collator,
        address _parachainStaking,
        address payable _stakingPool
    ) external {
        require(_stakingPool != address(0) && STAKING_POOL == address(0), "ALREADY_INIT");
        STAKING_POOL = _stakingPool;
        COLLATOR = _collator;
        staking = ParachainStaking(_parachainStaking);
    }

    function delegate(uint256 _delegation) external onlyStakingPool {
        staking.delegate(
                COLLATOR,
                _delegation,
                staking.candidateDelegationCount(COLLATOR),
                staking.delegatorDelegationCount(address(this))
        );
    }

    function delegatorBondMore(uint256 _delegation)
        external onlyStakingPool
    {
        staking.delegatorBondMore(COLLATOR, _delegation);
    }


    function scheduleDelegatorBondLess(uint256 _toUndelegate)
        external onlyStakingPool
    {
        staking.scheduleDelegatorBondLess(COLLATOR, _toUndelegate);
    }
    function scheduleRevokeDelegation() external onlyStakingPool {
        // we cannot revoke members that have made the minimum deposits
        staking.scheduleRevokeDelegation(COLLATOR);
    }

    
    function cancelDelegationRequest() external onlyStakingPool {
        staking.cancelDelegationRequest(COLLATOR);
    }

    function setAutoCompound(
        uint8 _value
    ) external onlyStakingPool {
        uint32 candidateAutoCompoundingDelegationCount = staking.candidateAutoCompoundingDelegationCount(COLLATOR);
        staking.setAutoCompound(
            COLLATOR,
            _value,
            candidateAutoCompoundingDelegationCount,
            staking.delegatorDelegationCount(address(this))
        );
    }

    function delegateWithAutoCompound(
        uint256 _amount,
        uint8 _autoCompound
    ) external onlyStakingPool {
        staking.delegateWithAutoCompound(
            COLLATOR,
            _amount,
            _autoCompound,
            staking.candidateDelegationCount(COLLATOR),
            staking.candidateAutoCompoundingDelegationCount(COLLATOR),
            staking.delegatorDelegationCount(address(this))
        );
    }

    function executeDelegationRequest() external onlyStakingPool {
        staking.executeDelegationRequest(address(this), COLLATOR);
    }

    function withdraw(uint256 _amount) external onlyStakingPool {
        (bool sent, ) = STAKING_POOL.call{value: _amount}("");
        require(sent, "EXEC_FAIL");
    }

    function deposit() external payable onlyStakingPool {

    }

}