// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../StrategyGeneralMiniChefBase.sol";
import "./IBeetsMasterChef.sol";

contract StrategyBeetsFarm is StrategyGeneralMiniChefBase {
    // Token addresses
    address public beets = 0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e;
    address public chef = 0x8166994d9ebBe5829EC86Bd81258149B87faCfd3;

    constructor(
        address depositor,
        address lp,
        uint256 pid
    )
        public
        StrategyGeneralMiniChefBase(
            beets,
            chef,
            pid,
            lp,
            depositor
        )
    {}

    // it calls Ice but it farms Spell
    function getHarvestable() external view override returns (uint256) {
        uint256 _pendingReward =
            IBeetsMasterChef(miniChef).pendingBeets(poolId, address(this));
        return _pendingReward;
    }
}
