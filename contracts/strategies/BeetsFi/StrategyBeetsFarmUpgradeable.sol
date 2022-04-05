// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../StrategyGeneralMiniChefBaseUpgradeable.sol";
import "./IBeetsMasterChef.sol";

contract StrategyBeetsFarmUpgradeable is StrategyGeneralMiniChefBaseUpgradeable {
    // Token addresses
    address public beets;
    address public chef;
    string public __NAME__;

    constructor() public {}

    function initialize(
        address depositor,
        address lp,
        uint256 pid,
        address _secondReward,
        string memory _name
    ) public initializer {
        __Ownable_init();
        beets = 0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e;
        chef = 0x8166994d9ebBe5829EC86Bd81258149B87faCfd3;
        __NAME__ = _name;
        initializeStrategyGeneralMiniChefBase(
            beets, 
            _secondReward, 
            chef, 
            pid, 
            lp, 
            depositor
        );
    }

    // it calls Ice but it farms Spell
    function getHarvestable() external view override returns (uint256) {
        uint256 _pendingReward =
            IBeetsMasterChef(miniChef).pendingBeets(poolId, address(this));
        return _pendingReward;
    }
}
