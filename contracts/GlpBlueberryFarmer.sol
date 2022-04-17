// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/MathUpgradeable.sol";

import {BaseStrategy} from "./strategy/BaseStrategy.sol";

import {IRewardRouter} from "interfaces/gmx/IRewardRouter.sol";
import {IRewardTracker} from "interfaces/gmx/IRewardTracker.sol";
import {IGlpManager} from "interfaces/gmx/IGlpManager.sol";
import {IGmxVault} from "interfaces/gmx/IGmxVault.sol";
import {IVester} from "interfaces/gmx/IVester.sol";

import {ISwapRouter} from "interfaces/uniswap/ISwapRouter.sol";
import {IQuoter} from "interfaces/uniswap/IQuoter.sol";

contract GlpBlueberryFarmer is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    // Strategy Variables
    uint24 public constant LOW_FEE = 3000;
    uint24 public constant HIGH_FEE = 10000;

    // Contract Addresses
    address public constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant GMX_ADDRESS = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address public constant ES_GMX_ADDRESS = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
    address public constant S_GLP_ADDRESS = 0x01AF26b74409d10e15b102621EDd29c326ba1c55;
    address public constant FS_GLP_ADDRESS = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
    address public constant GMX_ETH_POOL_ADDRESS = 0x80A9ae39310abf666A87C743d6ebBD0E8C42158E;
    address public constant REWARDS_ROUTER_ADDRESS = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address public constant VAULT_ADDRESS = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    // Contract Interfaces
    IERC20Upgradeable public constant WETH = IERC20Upgradeable(WETH_ADDRESS);
    IERC20Upgradeable public constant GMX = IERC20Upgradeable(GMX_ADDRESS);
    IERC20Upgradeable public constant ES_GMX = IERC20Upgradeable(ES_GMX_ADDRESS);
    IERC20Upgradeable public constant S_GLP = IERC20Upgradeable(S_GLP_ADDRESS);
    IERC20Upgradeable public constant FS_GLP = IERC20Upgradeable(FS_GLP_ADDRESS);
    IRewardRouter public constant REWARDS_ROUTER = IRewardRouter(REWARDS_ROUTER_ADDRESS);
    IGmxVault public constant GMX_VAULT = IGmxVault(VAULT_ADDRESS);

    ISwapRouter public router;
    IQuoter public quoter;
    IVester public vester;
    IGlpManager public glpManager;

    uint256 public vestingBufferBps;

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    function initialize(address _vault, address[] memory _swapConfig) public initializer {
        __BaseStrategy_init(_vault);

        router = ISwapRouter(_swapConfig[0]);
        quoter = IQuoter(_swapConfig[1]);

        want = FS_GLP_ADDRESS;
        vester = IVester(REWARDS_ROUTER.glpVester());
        glpManager = IGlpManager(REWARDS_ROUTER.glpManager());

        vestingBufferBps = 3_000;

        GMX.safeApprove(_swapConfig[0], type(uint256).max);
        WETH.safeApprove(REWARDS_ROUTER.glpManager(), type(uint256).max);
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
        if (balanceOfPool() != 0) {
            vester.withdraw();
        }
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        uint256 balance = balanceOfWant();
        uint256 rebalanceThreshold = _calcBuffer(balance - _amount);
        // if we withdraw too much, rebalance a bit to fix the buffer
        uint256 postWithdraw = balance + balanceOfPool() - _amount;
        if (balance < _amount || postWithdraw <= rebalanceThreshold) {
            vester.withdraw();
            _handleEsGmxVesting(_calcBuffer(postWithdraw));
        }
        // no-op, want is a fee staked token
        return _amount;
    }

    /// @notice Transfers `_amount` of want to the vault.
    /// @dev Strategy should have idle funds >= `_amount`.
    /// @param _amount Amount of want to be transferred to the vault.
    function _transferToVault(uint256 _amount) internal override {
        if (_amount > 0) {
            S_GLP.safeTransfer(vault, _amount);
        }
    }

    /// @dev no-op, want is a fee staked token
    function _isTendable() internal pure override returns (bool) {
        return false;
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        harvested = new TokenAmount[](2);
        harvested[0].token = WETH_ADDRESS;
        harvested[1].token = want;

        uint256 fsGlpBalance = FS_GLP.balanceOf(address(this));

        // Claim Rewards
        REWARDS_ROUTER.handleRewards(true, false, true, false, true, true, false);

        // Process WETH
        uint256 wethHarvested = WETH.balanceOf(address(this));
        if (wethHarvested > 0) {
            harvested[0].amount = wethHarvested;
            _processExtraToken(WETH_ADDRESS, wethHarvested);
        }

        // check to see if any gmx was vested
        uint256 gmxBalance = GMX.balanceOf(address(this));

        // Compound FS_GLP and report to vault
        if (gmxBalance > 0) {
            // Estimate Low Fee Output
            uint256 lowFeeOut = quoter.quoteExactInputSingle(GMX_ADDRESS, WETH_ADDRESS, LOW_FEE, gmxBalance, 0);

            // Estimate High Fee Output
            uint256 highFeeOut = quoter.quoteExactInputSingle(GMX_ADDRESS, WETH_ADDRESS, HIGH_FEE, gmxBalance, 0);

            // Select Best Fee
            uint24 swapFee = lowFeeOut > highFeeOut ? LOW_FEE : HIGH_FEE;

            // Swap
            router.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(GMX_ADDRESS, swapFee, WETH_ADDRESS),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: gmxBalance,
                    amountOutMinimum: 0
                })
            );

            uint256 wethBalance = WETH.balanceOf(address(this));
            // TODO: Find a way to estimate GLP min out
            REWARDS_ROUTER.mintAndStakeGlp(WETH_ADDRESS, wethBalance, 0, _getMinGlpOut(wethBalance));

            uint256 fsGlpHarvested = FS_GLP.balanceOf(address(this)) - fsGlpBalance;
            harvested[1].amount = fsGlpHarvested;
            _reportToVault(fsGlpHarvested);
        }

        _handleEsGmxVesting(_calcBuffer(balanceOfWant()));

        return harvested;
    }

    /// @dev optimizes esgmx play for maximal compounding and fee generation
    function _handleEsGmxVesting(uint256 _maxReserve) internal {
        uint256 esGmxBalance = ES_GMX.balanceOf(address(this));
        uint256 maxVest = vester.getMaxVestableAmount(address(this));
        uint256 stakedEsGmx = _stakedEsGmx();

        // always try to vest maximally, unstake if needed
        if (maxVest > esGmxBalance && stakedEsGmx != 0) {
            REWARDS_ROUTER.unstakeEsGmx(MathUpgradeable.min(stakedEsGmx, maxVest - esGmxBalance));
        }

        esGmxBalance = ES_GMX.balanceOf(address(this));

        // if we have esgmx, try to vest it in the glp vault
        if (esGmxBalance != 0) {
            uint256 canVest = MathUpgradeable.min(maxVest, esGmxBalance);
            uint256 reservationRatio = vester.getPairAmount(address(this), 1);
            uint256 toVest = MathUpgradeable.min(canVest, _maxReserve / reservationRatio);

            // only vest using reserve up to some % buffer of the GLP
            if (toVest != 0) {
                vester.deposit(toVest);
            }

            // stake remaining esgmx to earn weth, esgmx, and mp
            uint256 esGmxRemainingBalance = esGmxBalance - toVest;
            if (esGmxRemainingBalance != 0) {
                REWARDS_ROUTER.stakeEsGmx(esGmxRemainingBalance);
            }
        }
    }

    function _tend() internal override returns (TokenAmount[] memory tended) {
        return new TokenAmount[](0);
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        return vester.pairAmounts(address(this));
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        rewards = new TokenAmount[](2);
        uint256 claimableWeth = IRewardTracker(REWARDS_ROUTER.feeGlpTracker()).claimable(address(this));
        rewards[0] = TokenAmount(WETH_ADDRESS, claimableWeth);
        uint256 claimableGmx = IVester(REWARDS_ROUTER.glpVester()).claimable(address(this));
        rewards[1] = TokenAmount(GMX_ADDRESS, claimableGmx);
        return rewards;
    }

    function _calcBuffer(uint256 _target) internal returns (uint256) {
        return (_target * (MAX_BPS - vestingBufferBps)) / MAX_BPS;
    }

    function _stakedEsGmx() internal returns (uint256) {
        return IRewardTracker(REWARDS_ROUTER.feeGmxTracker()).depositBalances(address(this), REWARDS_ROUTER.bonusGmxTracker());
    }

    function _getMinGlpOut(uint256 _input) internal returns (uint256) {
        uint256 glpPrice = _glpPrice(true);
        return (_input * glpPrice) / GMX_VAULT.getMinPrice(WETH_ADDRESS);
    }

    function _glpPrice(bool _isBuying) internal returns (uint256) {
        uint256[] memory aums = glpManager.getAums();
        uint256 aum = _isBuying ? aums[0] : aums[1];
        return aum / FS_GLP.totalSupply();
    }
}
