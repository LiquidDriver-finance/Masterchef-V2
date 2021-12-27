// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../StrategyGeneralMasterChefBase.sol";
import "./ISpellMasterChef.sol";

contract StrategySpellFarm is StrategyGeneralMasterChefBase {
    // Token addresses
    address public spell = 0x468003B688943977e6130F4F68F23aad939a1040;
    address public masterChef = 0x37Cf490255082ee50845EA4Ff783Eb9b6D1622ce;

    constructor(
        address depositor,
        address lp,
        address token0,
        address token1,
        uint256 pid
    )
        public
        StrategyGeneralMasterChefBase(
            spell,
            masterChef,
            token0,
            token1,
            pid,
            lp,
            depositor
        )
    {}

    // it calls Ice but it farms Spell
    function getHarvestable() external view override returns (uint256) {
        uint256 _pendingReward =
            ISpellMasterChef(masterchef).pendingIce(poolId, address(this));
        return _pendingReward;
    }
}
