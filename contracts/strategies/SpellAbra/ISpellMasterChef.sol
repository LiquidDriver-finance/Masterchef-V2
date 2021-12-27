// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

// it calls Ice but it farms Spell
interface ISpellMasterChef {
    function pendingIce(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}