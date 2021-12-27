// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "hardhat/console.sol";

contract linSpiritStaker is OwnableUpgradeable {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public spirit;
  address public linSpiritStrategy;
  address public linSpirit;

  mapping(address => uint256) public userRewardDebt;
  mapping(address => uint256) public userAmount;

  uint256 public accRewardPerShare;
  uint256 public lastPendingReward;
  uint256 public curPendingReward;

  constructor() public {
  }

  function initialize(
    address _spirit,
    address _linSpirit,
    address _linSpiritStrategy
  ) public initializer {
    __Ownable_init();
    spirit = _spirit;
    linSpirit = _linSpirit;
    linSpiritStrategy = _linSpiritStrategy;
  }

  function deposit(uint256 _amount) external {
    _updateAccPerShare(msg.sender);
    _withdrawReward(msg.sender);

    if (_amount > 0) {
      IERC20(linSpirit).safeTransferFrom(msg.sender, address(this), _amount);
    }

    userAmount[msg.sender] = userAmount[msg.sender].add(_amount);

    _updateUserRewardDebts(msg.sender);
  }

  function withdraw(uint256 _amount) external {
    uint256 _balance = IERC20(linSpirit).balanceOf(address(this));
    require(_balance > 0, "No balance");
    require(userAmount[msg.sender] >= _amount, "withdraw: not good");

    _updateAccPerShare(msg.sender);
    _withdrawReward(msg.sender);

    if (_amount > _balance) {
      _amount = _balance;
    }

    if (_amount > 0) {
      IERC20(linSpirit).safeTransfer(msg.sender, _amount);
    }

    userAmount[msg.sender] = userAmount[msg.sender].sub(_amount);
    _updateUserRewardDebts(msg.sender);
  }

  function _updateAccPerShare(address _user) internal {
    curPendingReward = pendingReward();
    uint256 _totalSupply = IERC20(linSpirit).balanceOf(address(this));

    if (lastPendingReward > 0 && curPendingReward < lastPendingReward) {
      curPendingReward = 0;
      lastPendingReward = 0;
      accRewardPerShare = 0;
      userRewardDebt[_user] = 0;
      return;
    }

    if (_totalSupply == 0) {
      accRewardPerShare = 0;
      return;
    }

    uint256 _addedReward = curPendingReward.sub(lastPendingReward);
    accRewardPerShare = accRewardPerShare.add(
      (_addedReward.mul(1e36)).div(_totalSupply)
    );
  }

  function _updateUserRewardDebts(address _user) internal {
    userRewardDebt[_user] = userAmount[_user]
    .mul(accRewardPerShare)
    .div(1e36);
  }

  function pendingReward() public view returns (uint256) {
    return IERC20(spirit).balanceOf(address(this));
  }

  function pendingRewardOfUser(address user) public view returns (uint256) {
    uint256 _totalSupply = IERC20(linSpirit).balanceOf(address(this));
    uint256 _userAmount = userAmount[user];
    if (_totalSupply == 0) return 0;

    uint256 _allPendingReward = pendingReward();
    if (_allPendingReward < lastPendingReward) return 0;
    uint256 _addedReward = _allPendingReward.sub(lastPendingReward);
    uint256 _newAccRewardPerShare = accRewardPerShare.add(
        (_addedReward.mul(1e36)).div(_totalSupply)
    );
    uint256 _pendingReward = _userAmount.mul(_newAccRewardPerShare).div(1e36).sub(
      userRewardDebt[user]
    );

    return _pendingReward;
  }

  function _withdrawReward(address _user) internal {
    uint256 _pending = userAmount[_user]
      .mul(accRewardPerShare)
      .div(1e36)
      .sub(userRewardDebt[_user]);
      
    uint256 _balance = IERC20(spirit).balanceOf(address(this));
    if (_balance < _pending) {
      _pending = _balance;
    }

    IERC20(spirit).safeTransfer(_user, _pending);
    lastPendingReward = curPendingReward.sub(_pending);
  }

  function setLinSpiritStrategy(address _strategy) public onlyOwner {
    linSpiritStrategy = _strategy;
  }
}
