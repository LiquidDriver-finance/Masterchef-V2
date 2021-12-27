// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ISpiritDistributor{
  function claim() external;
  function claim(address) external;
}