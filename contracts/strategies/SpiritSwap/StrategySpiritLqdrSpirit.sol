// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "../StrategyGeneralMasterChefBase.sol";
import "./ISpiritMasterChef.sol";

contract StrategySpiritLqdrSpirit is StrategyGeneralMasterChefBase {
    // Token addresses
    address public spirit = 0x5Cc61A78F164885776AA610fb0FE1257df78E59B;
    address public masterChef = 0x9083EA3756BDE6Ee6f27a6e996806FBD37F6F093;
    address public spirit_lqdr_spirit_lp = 0xFeBbfeA7674720cEdD35e9384d07F235365c1B3e;
    address public lqdr = 0x10b620b2dbAC4Faa7D7FFD71Da486f5D44cd86f9;

    constructor(
      address treasury,
      address depositor
    )
      public
      StrategyGeneralMasterChefBase(
        spirit,
        masterChef,
        lqdr,
        spirit,
        33, // pool id
        spirit_lqdr_spirit_lp,
        depositor
      )
    {}

    function getHarvestable() external override view returns (uint256) {
        uint256 _pendingReward = ISpiritMasterChef(masterchef).pendingSpirit(poolId, address(this));
        return _pendingReward;
    }
}
