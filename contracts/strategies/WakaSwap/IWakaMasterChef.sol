// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

interface IWakaMasterChef {
    function pendingWaka(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}
