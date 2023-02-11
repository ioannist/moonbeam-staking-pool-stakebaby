// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.3;
import "../StakingPool.sol";

contract StakingPool_mock is StakingPool {
    
    function _isProxy(address _manager) internal view override returns(bool) {
        return true;
    }

    function simulateRewards() external payable {
        
    }
}