// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IStrategy.sol";

contract LiquidDepositor is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public masterChef;
  mapping(address => address) public strategies;

  struct PoolInfo {
    IERC20 lpToken;
    IStrategy strategy;
  }

  PoolInfo[] public poolInfo;

  constructor(address _masterChef) public {
    masterChef = _masterChef;
  }

  modifier onlyMasterChef {
    require(msg.sender == masterChef, "Not masterChef");
    _;
  }

  function add(IERC20 _lpToken, IStrategy _strategy) external onlyOwner {
    poolInfo.push(
        PoolInfo({
            lpToken: _lpToken,
            strategy: _strategy
        })
    );
    strategies[address(_lpToken)] = address(_strategy);
  }

  function set(uint256 _pid, IStrategy _strategy) external onlyOwner {
    poolInfo[_pid].strategy = _strategy;
    strategies[address(poolInfo[_pid].lpToken)] = address(_strategy);
  }

  function setMasterChefAddress(address _masterChef) external onlyOwner {
    masterChef = _masterChef;
  }

  function balanceOf(address token) external view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  function deposit(uint256 amount, address token) external {
    require(amount > 0, "Cannot deposit 0");
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
  }

  function depositToStrategy(uint256 amount, address token) external {
    require(amount > 0, "Cannot deposit 0");
    address strategy = strategies[token];
    IERC20(token).safeTransfer(strategy, amount);
  }

  function withdraw(uint256 amount, address token) public onlyMasterChef returns (uint256) {
    require(amount > 0, "Cannot withdraw 0");
    uint256 balance = IERC20(token).balanceOf(address(this));
    address strategy = strategies[token];
    if (amount > balance) {
      uint256 missing = amount.sub(balance);
      IStrategy(strategy).withdraw(missing);
    }

    balance = IERC20(token).balanceOf(address(this));
    if (amount > balance) {
      amount = balance;
    }

    if (amount > 0) {
      IERC20(token).safeTransfer(msg.sender, amount);
    }
    
    return amount;
  }

  function withdrawAllFromStrategy(address token) public onlyOwner returns (uint256) {
    address strategy = strategies[token];
    uint256 balance = IStrategy(strategy).balanceOf();
    if (balance > 0) {
      IStrategy(strategy).withdrawAll();
    }

    return balance;
  }

  function withdrawAllToMasterChef(address token) public onlyOwner returns (uint256) {
    require(masterChef != address(0), "MasterChef is not set");
    withdrawAllFromStrategy(token);
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
      IERC20(token).safeTransfer(masterChef, balance);
    }

    return balance;
  }
}