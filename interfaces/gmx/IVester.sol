// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IVester {
  
  function deposit(uint256 _amount) external;

  function withdraw() external;

  function balanceOf(address _account) external view returns (uint256);

  function claimable(address _account) external view returns (uint256);

  function getMaxVestableAmount(address _account) external view returns (uint256);

  function pairAmounts(address _account) external view returns (uint256);

  function getPairAmount(address _account, uint256 _esAmount) external view returns (uint256);
}
