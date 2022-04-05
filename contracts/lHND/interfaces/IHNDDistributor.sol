// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IHNDDistributor{
  function claim() external;
  function claim(address) external;
}