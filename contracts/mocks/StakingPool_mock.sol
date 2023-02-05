// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
import "../StakingPool.sol";

contract StakingPool_mock is StakingPool {

    // reducible balance + inUndelegation + delegatedTotal + = total pool funds in underlying
    // Current total amount of underlying delegatedTotal to collators
    uint256 public delegatedTotal;

    // Map of collators to delegation amounts
    mapping(address => uint256) delegations;


    function _getDelegation(address _collator) internal view override returns(uint256) {
        return delegations[_collator];
    }

    function _addToDelegatedTotal(uint256 _amount, bool _minus) internal override {
         if (_minus) {
            delegatedTotal -= _amount;
         } else {
            delegatedTotal += _amount;
         }
    }

    function _addToDelegations(address _collator, uint256 _amount, bool _minus) internal override {
        if (_minus) {
            delegations[_collator] -= _amount;
        } else {
            delegations[_collator] += _amount;
        }

    }

}
