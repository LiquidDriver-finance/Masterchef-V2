// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IHNDMinter{
  function mint(address) external;
  function mint_many(address[] calldata _gauge_addrs) external;
}