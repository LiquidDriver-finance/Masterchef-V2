// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./StrategyBaseUpgradeable.sol";
import "../interfaces/ILiquidDepositor.sol";
import "../lHND/interfaces/IHNDGauge.sol";
import "../lHND/interfaces/ILiHNDStrategy.sol";
import "hardhat/console.sol";

contract StrategyGeneralHndBase is StrategyBaseUpgradeable {
    // Token addresses
    address public gauge;
    address public rewardToken;
    address public liHNDStrategy;
    string public __NAME__;

    constructor() public {}

    function initialize(
        address _rewardToken,
        address _gauge,
        address _lp,
        address _depositor,
        address _liHNDStrategy,
        string memory _name
    ) public initializer {
        initializeStrategyBase(_lp, _depositor);
        rewardToken = _rewardToken;
        gauge = _gauge;
        liHNDStrategy = _liHNDStrategy;
        __NAME__ = _name;
    }
    
    function balanceOfPool() public override view returns (uint256) {
        uint256 amount = IHNDGauge(gauge).balanceOf(liHNDStrategy);
        return amount;
    }

    function getHarvestable() external view returns (uint256) {
        uint256 _pendingReward = IHNDGauge(gauge).claimable_reward(liHNDStrategy, rewardToken);
        return _pendingReward;
    }

    // **** Setters ****

    function deposit() public override {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeTransfer(liHNDStrategy, _want);
            ILiHNDStrategy(liHNDStrategy).deposit(gauge, want);
        }
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        ILiHNDStrategy(liHNDStrategy).withdraw(gauge, want, _amount);
        return _amount;
    }

    // **** State Mutations ****

    function harvest() public override onlyBenevolent {
        ILiHNDStrategy(liHNDStrategy).claimGaugeReward(gauge, depositor);
    }
}
