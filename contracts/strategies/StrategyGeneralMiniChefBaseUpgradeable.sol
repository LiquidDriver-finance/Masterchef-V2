// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./StrategyBaseUpgradeable.sol";
import "../interfaces/IMiniChefV2.sol";
import "../interfaces/ILiquidDepositor.sol";

abstract contract StrategyGeneralMiniChefBaseUpgradeable  is StrategyBaseUpgradeable {
    // Token addresses
    address public miniChef;
    address public rewardToken;
    address public secondRewardToken;

    uint256 public poolId;

    constructor() public {}

    function initializeStrategyGeneralMiniChefBase(
        address _rewardToken,
        address _secondRewardToken,
        address _miniChef,
        uint256 _poolId,
        address _lp,
        address _depositor
    ) public initializer {
        initializeStrategyBase(_lp, _depositor);
        poolId = _poolId;
        rewardToken = _rewardToken;
        secondRewardToken = _secondRewardToken;
        miniChef = _miniChef;
    }
    
    function balanceOfPool() public override view returns (uint256) {
        (uint256 amount, ) = IMiniChefV2(miniChef).userInfo(poolId, address(this));
        return amount;
    }

    function getHarvestable() external virtual view returns (uint256) {
        uint256 _pendingReward = IMiniChefV2(miniChef).pendingReward(poolId, address(this));
        return _pendingReward;
    }

    // **** Setters ****

    function deposit() public override {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(miniChef, 0);
            IERC20(want).safeApprove(miniChef, _want);
            IMiniChefV2(miniChef).deposit(poolId, _want, address(this));
        }
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        IMiniChefV2(miniChef).withdrawAndHarvest(poolId, _amount, address(this));
        return _amount;
    }

    // **** State Mutations ****

    function harvest() public override onlyBenevolent {
        IMiniChefV2(miniChef).harvest(poolId, ILiquidDepositor(depositor).treasury());
        uint256 _rewardBalance = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).safeTransfer(
            ILiquidDepositor(depositor).treasury(),
            _rewardBalance
        );
        if (secondRewardToken != address(0)) {
            uint256 _secondRewardBalance = IERC20(secondRewardToken).balanceOf(address(this));
            IERC20(secondRewardToken).safeTransfer(
                ILiquidDepositor(depositor).treasury(),
                _secondRewardBalance
            );
        }
    }
}
