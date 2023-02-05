// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import OpenZeppelin Contract
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// This ERC-20 contract mints the specified amount of tokens to the contract creator.
contract TokenLiquidStaking is ERC20  {

    address payable STAKING_POOL;

    constructor(uint256 initialSupply) ERC20("TokenLiquidStaking", "cdGLMR") 
    {
        _mint(msg.sender, initialSupply);
    }

    // Allows function calls only from StakingPool
    modifier onlyStakingPool() {
        require(msg.sender == STAKING_POOL);
        _;
    }

    function initialize(address payable _stakingPool, address _daoStaking) external  {
        require(_stakingPool != address(0) && STAKING_POOL == address(0), "ALREADY_INIT");
    }

    function mintToAddress(address _to, uint256 _amount) public onlyStakingPool {
        _mint(_to, _amount);
    }

    function burnFromAddress(address _from, uint256 _amount) public onlyStakingPool {
        _burn(_from, _amount);
    }
}
