// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IRewardRouter {

  function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;

  function stakeEsGmx(uint256 _amount) external;

  function stakeGmx(uint256 _amount) external;

  function unstakeEsGmx(uint256 _amount) external;

  function unstakeGmx(uint256 _amount) external;

  function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
  
  function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);

  function claimable(address _account) external view returns (uint256);

  function feeGlpTracker() external view returns (address);

  function feeGmxTracker() external view returns (address);

  function bonusGmxTracker() external view returns (address);

  function gmxVester() external view returns (address);

  function glpVester() external view returns (address);
  
  function glpManager() external view returns (address);
}
