// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IVeHND{
    function create_lock(uint256,uint256) external;
    function withdraw() external;
    function increase_amount(uint256) external;
    function increase_unlock_time(uint256) external;
    function balanceOf(address) external view returns(uint256);
}