// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IHNDGaugeProxy{
  function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external;
  function vote_for_gauge_weights(address, uint256) external;
}