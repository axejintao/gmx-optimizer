// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IGlpManager {
  
  function getAums() external view returns (uint256[] memory);

  function getAum(bool _maximize) external view returns (uint256);
}
