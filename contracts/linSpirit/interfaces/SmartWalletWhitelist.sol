// SPDX-License-Identifier: MIT

/**
 *Submitted for verification at FtmScan.com on 2021-08-23
*/

/**
 *Submitted for verification at Etherscan.io on 2020-08-24
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface SmartWalletChecker {
    function check(address) external view returns (bool);
}

contract SmartWalletWhitelist {
    
    mapping(address => bool) public wallets;
    address public dao;
    address public checker;
    address public future_checker;
    
    event ApproveWallet(address);
    event RevokeWallet(address);
    
    constructor(address _dao) public {
        dao = _dao;
        wallets[0x4D5362dd18Ea4Ba880c829B0152B7Ba371741E59] = true;
        emit ApproveWallet(0x4D5362dd18Ea4Ba880c829B0152B7Ba371741E59);
    }
    
    function commitSetChecker(address _checker) external {
        require(msg.sender == dao, "!dao");
        future_checker = _checker;
    }
    
    function applySetChecker() external {
        require(msg.sender == dao, "!dao");
        checker = future_checker;
    }
    
    function approveWallet(address _wallet) public {
        require(msg.sender == dao, "!dao");
        wallets[_wallet] = true;
        
        emit ApproveWallet(_wallet);
    }
    function revokeWallet(address _wallet) external {
        require(msg.sender == dao, "!dao");
        wallets[_wallet] = false;
        
        emit RevokeWallet(_wallet);
    }
    
    function check(address _wallet) external view returns (bool) {
        bool _check = wallets[_wallet];
        if (_check) {
            return _check;
        } else {
            if (checker != address(0)) {
                return SmartWalletChecker(checker).check(_wallet);
            }
        }
        return false;
    }
}