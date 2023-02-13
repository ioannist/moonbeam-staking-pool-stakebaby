// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import OpenZeppelin Contract
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
