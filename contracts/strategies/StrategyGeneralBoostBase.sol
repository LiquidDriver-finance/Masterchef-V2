// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./StrategyBase.sol";
import "../interfaces/ILiquidDepositor.sol";
import "../linSpirit/interfaces/ISpiritGauge.sol";
import "../linSpirit/interfaces/ILinSpiritStrategy.sol";
import "hardhat/console.sol";

contract StrategyGeneralBoostBase is StrategyBase {
    // Token addresses
    address public gauge;
    address public rewardToken;
    address public linSpiritStrategy;

    constructor(
        address _rewardToken,
        address _gauge,
        address _lp,
        address _depositor,
        address _linSpiritStrategy
    )
        public
        StrategyBase(
            _lp,
            _depositor
        )
    {
        rewardToken = _rewardToken;
        gauge = _gauge;
        linSpiritStrategy = _linSpiritStrategy;
    }
    
    function balanceOfPool() public override view returns (uint256) {
        uint256 amount = ISpiritGauge(gauge).balanceOf(linSpiritStrategy);
        return amount;
    }

    function getHarvestable() external view returns (uint256) {
        uint256 _pendingReward = ISpiritGauge(gauge).rewards(linSpiritStrategy);
        return _pendingReward;
    }

    // **** Setters ****

    function deposit() public override {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeTransfer(linSpiritStrategy, _want);
            ILinSpiritStrategy(linSpiritStrategy).deposit(gauge, want);
        }
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        ILinSpiritStrategy(linSpiritStrategy).withdraw(gauge, want, _amount);
        return _amount;
    }

    // **** State Mutations ****

    function harvest() public override onlyBenevolent {
        ILinSpiritStrategy(linSpiritStrategy).claimGaugeReward(gauge);
        uint256 _rewardBalance = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).safeTransfer(
            ILiquidDepositor(depositor).treasury(),
            _rewardBalance
        );
    }
}
