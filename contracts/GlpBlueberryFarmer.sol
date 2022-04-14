// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";

import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";

import {IRewardRouter} from "interfaces/gmx/IRewardRouter.sol";

contract GlpBlueberryFarmer is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    // Contract Addresses
    address public constant REWARDS_ROUTER_ADDRESS = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address public constant WETH_ADDRESS = 0x82af49447d8a07e3bd95bd0d56f35241523fbab1;
    address public constant GMX_ADDRESS = 0xfc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a;
    address public constant GMX_ETH_POOL_ADDRESS = 0x80A9ae39310abf666A87C743d6ebBD0E8C42158E;

    // Contract Interfaces
    IRewardRouter public constant REWARDS_ROUTER = IRewardRouter(REWARDS_ROUTER_ADDRESS);
    IERC20Upgradeable public constant WETH = IERC20Upgradeable(WETH_ADDRESS);
    IERC20Upgradeable public constant GMX = IERC20Upgradeable(GMX_ADDRESS);
    IERC20Upgradeable public constant FS_GLP = IERC20Upgradeable(want);

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address[1] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);
        want = _wantConfig[0];
    }
    
    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "GlpBlueberryFarmer";
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want; // FS_GLP_ADDRESS
        protectedTokens[1] = WETH_ADDRESS;
        protectedTokens[2] = GMX_ADDRESS;
        return protectedTokens;
    }

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        // no-op, want is a fee staked token
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        // no-op, want is a fee staked token
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        // no-op, want is a fee staked token
    }

    /// @dev no-op, want is a fee staked token
    function _isTendable() internal override pure returns (bool) {
        return false;
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        TokenAmount[] memory harvested = new TokenAmount[](2);
        harvested[0].token = WETH_ADDRESS;
        harvested[1].token = want;

        uint256 fsGlpBalance = FS_GLP.balanceOf(address(this));

        // Claim GMX Rewards
        REWARDS_ROUTER.handleRewards(true, false, true, false, false, true, false);

        // Trivially Process WETH
        // TODO: Create a WETH Strategy
        uint256 wethHarvested = WETH.balanceOf(address(this));
        harvested[0].amount = wethHarvested;
        _processExtraToken(WETH_ADDRESS, wethHarvested);

        // Compound FS_GLP and report to vault
        _compoundGlp();
        uint256 fsGlpHarvested = FS_GLP.balanceOf(address(this)) - fsGlpBalance;
        harvested[1].amount = fsGlpHarvested;
        _reportToVault(fsGlpHarvested);

        return harvested;
    }

    function _tend() internal override returns (TokenAmount[] memory tended){
        return new TokenAmount[](0);
    }

    function _compoundGlp() internal {
        // setup token approvals for swap
        GMX.safeApprove(recipient, 0);
        GMX.safeApprove(recipient, amount);

        // TODO: UniV3 execute the swap

        uint256 wethOut = WETH.balanceOf(address(this));

        // TODO: Find a way to estimate GLP min out
        REWARDS_ROUTER.mintAndStakeGlp(WETH_ADDRESS, wethOut, 0, 0);
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        // Change this to return the amount of want invested in another protocol
        return FS_GLP.balanceOf(address(this));
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        return new TokenAmount[](0);
    }
}
