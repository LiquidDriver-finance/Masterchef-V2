// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IInSpirit.sol";
import "./interfaces/ISpiritGauge.sol";
import "./interfaces/ISpiritGaugeProxy.sol";
import "./interfaces/ISpiritDistributor.sol";
import "hardhat/console.sol";

contract linSpiritStrategy is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public inSpirit;
    address public spirit;
    address public linSpiritManager;
    address public gaugeProxy;
    mapping(address => bool) isBoostStrategy;

    constructor() public {}

    function initialize(
        address _spirit,
        address _inSpirit,
        address _gaugeProxy
    ) public initializer {
        __Ownable_init();
        spirit = _spirit;
        inSpirit = _inSpirit;
        gaugeProxy = _gaugeProxy;
    }

    modifier restricted {
        require(msg.sender == owner() || msg.sender == linSpiritManager, "Auth failed");
        _;
    }

    modifier ownerOrBoostStrategy {
        require(msg.sender == owner() || isBoostStrategy[msg.sender], "Permission denied");
        _;
    }

    function setManager(address _manager) external onlyOwner {
        linSpiritManager = _manager;
    }

    function whitelistBoostStrategy(address _strategy) external onlyOwner {
        isBoostStrategy[_strategy] = true;
    }

    function blacklistBoostStrategy(address _strategy) external onlyOwner {
        isBoostStrategy[_strategy] = false;
    }

    function createLock(uint256 _amount, uint256 _unlockTime) external restricted {
        uint256 _balance = IERC20(spirit).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds spirit balance");
        IERC20(spirit).safeApprove(inSpirit, 0);
        IERC20(spirit).safeApprove(inSpirit, _amount);
        IInSpirit(inSpirit).create_lock(_amount, _unlockTime);
    }

    function release() external restricted {
        IInSpirit(inSpirit).withdraw();
    }

    function increaseAmount(uint256 _amount) external restricted {
        uint256 _balance = IERC20(spirit).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds spirit balance");
        IERC20(spirit).safeApprove(inSpirit, 0);
        IERC20(spirit).safeApprove(inSpirit, _amount);
        IInSpirit(inSpirit).increase_amount(_amount);
    }

    function increaseTime(uint256 _unlockTime) external restricted {
        IInSpirit(inSpirit).increase_unlock_time(_unlockTime);
    }

    function deposit(address _gauge, address _underlying) external ownerOrBoostStrategy {
        uint256 _balance = IERC20(_underlying).balanceOf(address(this));
        IERC20(_underlying).safeApprove(_gauge, _balance);
        ISpiritGauge(_gauge).depositAll();
    }

    function withdraw(
        address _gauge,
        address _underlying,
        uint256 _amount
    ) external ownerOrBoostStrategy {
        ISpiritGauge(_gauge).withdraw(_amount);
        uint256 _balance = IERC20(_underlying).balanceOf(address(this));
        require(_balance >= _amount, "Withdraw failed");
        IERC20(_underlying).safeTransfer(msg.sender, _amount);
    }

    function withdrawAll(address _gauge, address _underlying) external ownerOrBoostStrategy {
        ISpiritGauge(_gauge).withdrawAll();
        uint256 _balance = IERC20(_underlying).balanceOf(address(this));
        IERC20(_underlying).safeTransfer(msg.sender, _balance);
    }

    function balanceOfInSpirit() external view returns (uint256) {
        return IInSpirit(inSpirit).balanceOf(address(this));
    }

    function claimGaugeReward(address _gauge) external ownerOrBoostStrategy {
        ISpiritGauge(_gauge).getReward();
        uint256 _rewardBalance = IERC20(spirit).balanceOf(address(this));
        IERC20(spirit).safeTransfer(msg.sender, _rewardBalance);
    }

    function claimInSpiritReward(address _feeDistributor, address _recipent) external onlyOwner {
        ISpiritDistributor(_feeDistributor).claim();
        uint256 _balance = IERC20(spirit).balanceOf(address(this));
        IERC20(spirit).safeTransfer(_recipent, _balance);
    }

    function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external onlyOwner {
        ISpiritGaugeProxy(gaugeProxy).vote(_tokenVote, _weights);
    }
}
