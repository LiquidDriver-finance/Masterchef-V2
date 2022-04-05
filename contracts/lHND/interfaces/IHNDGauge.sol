// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IHNDGauge{
  function deposit(uint256) external;
  function depositAll() external;
  function withdraw(uint256) external;
  function withdrawAll() external;
  function claim_rewards(address, address) external;
  function balanceOf(address) external view returns(uint256);
  function claimable_reward(address, address) external view returns(uint256);
}