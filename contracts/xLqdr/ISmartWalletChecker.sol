// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface SmartWalletChecker {
    function check(address) external view returns (bool);
}