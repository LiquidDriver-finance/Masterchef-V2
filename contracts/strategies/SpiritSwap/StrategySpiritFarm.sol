// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "../StrategyGeneralMasterChefBase.sol";
import "./ISpiritMasterChef.sol";

contract StrategySpiritFarm is StrategyGeneralMasterChefBase {
    // Token addresses
    address public spirit = 0x5Cc61A78F164885776AA610fb0FE1257df78E59B;
    address public masterChef = 0x9083EA3756BDE6Ee6f27a6e996806FBD37F6F093;

    constructor(
      address depositor,
      address lp,
      address token0,
      address token1,
      uint256 pid
    )
      public
      StrategyGeneralMasterChefBase(
        spirit,
        masterChef,
        token0,
        token1,
        pid, // pool id
        lp,
        depositor
      )
    {}

    function getHarvestable() external override view returns (uint256) {
        uint256 _pendingReward = ISpiritMasterChef(masterchef).pendingSpirit(poolId, address(this));
        return _pendingReward;
    }
}
