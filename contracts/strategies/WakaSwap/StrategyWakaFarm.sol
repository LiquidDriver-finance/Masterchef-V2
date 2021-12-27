// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "../StrategyGeneralMasterChefBase.sol";
import "./IWakaMasterChef.sol";

contract StrategyWakaFarm is StrategyGeneralMasterChefBase {
    // Token addresses
    address public waka = 0xf61cCdE1D4bB76CeD1dAa9D4c429cCA83022B08B;
    address public masterChef = 0xaEF349E1736b8A4B1B243A369106293c3a0b9D09;

    constructor(
      address depositor,
      address lp,
      address token0,
      address token1,
      uint256 pid
    )
      public
      StrategyGeneralMasterChefBase(
        waka,
        masterChef,
        token0,
        token1,
        pid, // pool id
        lp,
        depositor
      )
    {}

    function getHarvestable() external override view returns (uint256) {
        uint256 _pendingReward = IWakaMasterChef(masterchef).pendingWaka(poolId, address(this));
        return _pendingReward;
    }
}
