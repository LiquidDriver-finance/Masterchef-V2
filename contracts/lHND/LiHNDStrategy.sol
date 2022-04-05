// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IVeHND.sol";
import "./interfaces/IHNDGauge.sol";
import "./interfaces/IHNDGaugeProxy.sol";
import "./interfaces/IHNDDistributor.sol";
import "../interfaces/ILiquidDepositor.sol";
import "./interfaces/IHNDMinter.sol";
import "hardhat/console.sol";

contract LiHNDStrategy is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public veHND;
    address public HND;
    address public liHNDManager;
    address public gaugeProxy;
    mapping(address => bool) isBoostStrategy;

    address public liHNDChef;
    address public xLQDRTreasury;

    uint256 public feeGauge;
    uint256 public feeStaking;
    uint256 public feeX;
    uint256 public feeMax;

    address public hndMinter;

    constructor() public {}

    function initialize(
        address _HND,
        address _veHND,
        address _gaugeProxy,
        address _xLQDRTreasury,
        uint256 _feeGauge,
        uint256 _feeStaking,
        uint256 _feeX
    ) public initializer {
        __Ownable_init();
        HND = _HND;
        veHND = _veHND;
        gaugeProxy = _gaugeProxy;
        xLQDRTreasury = _xLQDRTreasury;

        feeMax = _feeGauge.add(_feeStaking).add(_feeX);
        require(feeMax > 0, "Fee Values are not correct.");
        feeGauge = _feeGauge;
        feeStaking = _feeStaking;
        feeX = _feeX;
    }

    modifier restricted {
        require(msg.sender == owner() || msg.sender == liHNDManager, "Auth failed");
        _;
    }

    modifier ownerOrBoostStrategy {
        require(msg.sender == owner() || isBoostStrategy[msg.sender], "Permission denied");
        _;
    }

    function setManager(address _manager) external onlyOwner {
        liHNDManager = _manager;
    }

    function setLiHNDChef(address _liHNDChef) external onlyOwner {
        liHNDChef = _liHNDChef;
    }

    function setXLQDRTreasury(address _xLQDRTreasury) external onlyOwner {
        xLQDRTreasury = _xLQDRTreasury;
    }

    function setHndMinter(address _hndMinter) external onlyOwner {
        hndMinter = _hndMinter;
    }

    function setFeeValues(uint256 _feeGauge, uint256 _feeStaking, uint256 _feeX) external onlyOwner {
        feeMax = _feeGauge.add(_feeStaking).add(_feeX);
        require(feeMax > 0, "Fee Values are not correct.");
        feeGauge = _feeGauge;
        feeStaking = _feeStaking;
        feeX = _feeX;
    }

    function whitelistBoostStrategy(address _strategy) external onlyOwner {
        isBoostStrategy[_strategy] = true;
    }

    function blacklistBoostStrategy(address _strategy) external onlyOwner {
        isBoostStrategy[_strategy] = false;
    }

    function createLock(uint256 _amount, uint256 _unlockTime) external restricted {
        uint256 _balance = IERC20(HND).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds HND balance");
        IERC20(HND).safeApprove(veHND, 0);
        IERC20(HND).safeApprove(veHND, _amount);
        IVeHND(veHND).create_lock(_amount, _unlockTime);
    }

    function release() external restricted {
        IVeHND(veHND).withdraw();
    }

    function increaseAmount(uint256 _amount) external restricted {
        uint256 _balance = IERC20(HND).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds HND balance");
        IERC20(HND).safeApprove(veHND, 0);
        IERC20(HND).safeApprove(veHND, _amount);
        IVeHND(veHND).increase_amount(_amount);
    }

    function increaseTime(uint256 _unlockTime) external restricted {
        IVeHND(veHND).increase_unlock_time(_unlockTime);
    }

    function deposit(address _gauge, address _underlying) external ownerOrBoostStrategy {
        uint256 _balance = IERC20(_underlying).balanceOf(address(this));
        IERC20(_underlying).safeApprove(_gauge, 0);
        IERC20(_underlying).safeApprove(_gauge, _balance);
        IHNDGauge(_gauge).deposit(_balance);
    }

    function withdraw(
        address _gauge,
        address _underlying,
        uint256 _amount
    ) external ownerOrBoostStrategy {
        IHNDGauge(_gauge).withdraw(_amount);
        uint256 _balance = IERC20(_underlying).balanceOf(address(this));
        require(_balance >= _amount, "Withdraw failed");
        IERC20(_underlying).safeTransfer(msg.sender, _amount);
    }

    function withdrawAll(address _gauge, address _underlying) external ownerOrBoostStrategy {
        uint256 _balance = IHNDGauge(_gauge).balanceOf(address(this));
        IHNDGauge(_gauge).withdraw(_balance);
        IERC20(_underlying).safeTransfer(msg.sender, _balance);
    }

    function balanceOfVeHND() external view returns (uint256) {
        return IVeHND(veHND).balanceOf(address(this));
    }

    function claimGaugeReward(address _gauge, address _depositor) external ownerOrBoostStrategy {
        require(feeMax > 0, "feeMax is not set");
        IHNDGauge(_gauge).claim_rewards(address(this), address(this));
        IHNDMinter(hndMinter).mint(_gauge);

        uint256 _balance = IERC20(HND).balanceOf(address(this));
        uint256 _amountGauge = _balance.mul(feeGauge).div(feeMax);
        uint256 _amountStaking = _balance.mul(feeStaking).div(feeMax);
        uint256 _amountXLqdr = _balance.sub(_amountGauge).sub(_amountStaking);

        IERC20(HND).safeTransfer(_depositor, _amountGauge);
        IERC20(HND).safeTransfer(liHNDChef, _amountStaking);
        IERC20(HND).safeTransfer(xLQDRTreasury, _amountXLqdr);

        ILiquidDepositor(_depositor).setDistributionRate(_amountGauge);
    }

    function claimVeHNDReward(address _feeDistributor, address _recipent) external onlyOwner {
        IHNDDistributor(_feeDistributor).claim();
        uint256 _balance = IERC20(HND).balanceOf(address(this));
        IERC20(HND).safeTransfer(_recipent, _balance);
    }

    function vote(address[] calldata _gaugeAddresses, uint256[] calldata _weights) external onlyOwner {
        require(_gaugeAddresses.length == _weights.length, "Token length doesn't match");
        uint256 _length = _gaugeAddresses.length;

        for (uint256 _i = 0; _i < _length; _i ++) {
            IHNDGaugeProxy(gaugeProxy).vote_for_gauge_weights(_gaugeAddresses[_i], _weights[_i]);
        }
    }
}
