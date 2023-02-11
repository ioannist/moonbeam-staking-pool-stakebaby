// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import OpenZeppelin Contract
import "./interfaces/StakingInterface.sol";
import "./TokenLiquidStaking.sol";

contract Claimable {
    address STAKING_POOL;

    // Delegator claimable amounts
    mapping(address => uint256) public claimables;

    modifier onlyStakingPool() {
        require(msg.sender == STAKING_POOL, "NOT_POOL");
        _;
    }

    function initialize(address _stakingPool) external payable {
        require(
            _stakingPool != address(0) && STAKING_POOL == address(0),
            "ALREADY_INIT"
        );
        STAKING_POOL = _stakingPool;
    }

    function claim(address _delegator) external {
        uint256 amount = claimables[_delegator];
        require(amount > 0, "ZERO_CLAIM");
        claimables[_delegator] = 0;
        (bool sent, ) = _delegator.call{value: amount}("");
        require(sent, "TRANSFER_FAIL");
    }

    function depositClaim(address _delegator) external payable onlyStakingPool {
        claimables[_delegator] += msg.value;
    }

}
