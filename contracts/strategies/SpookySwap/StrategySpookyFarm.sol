// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "../StrategyGeneralMasterChefBase.sol";
import "./ISpookyMasterChef.sol";

contract StrategySpookyFarm is StrategyGeneralMasterChefBase {
    // Token addresses
    address public boo = 0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE;
    address public masterChef = 0x2b2929E785374c651a81A63878Ab22742656DcDd;

    constructor(
      address depositor,
      address lp,
      address token0,
      address token1,
      uint256 pid
    )
      public
      StrategyGeneralMasterChefBase(
        boo,
        masterChef,
        token0,
        token1,
        pid, // pool id
        lp,
        depositor
      )
    {}

    function getHarvestable() external override view returns (uint256) {
        uint256 _pendingReward = ISpookyMasterChef(masterchef).pendingBOO(poolId, address(this));
        return _pendingReward;
    }
}
