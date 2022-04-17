// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import {Vault} from "./Vault.sol";
import {IStrategy} from "@badger-finance/interfaces/badger/IStrategy.sol";

// Alex, Forgive My Sins
contract TheVault is Vault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Token that affords allowances for transfer of fsGLP
    IERC20Upgradeable constant tokenProxy = IERC20Upgradeable(0x01AF26b74409d10e15b102621EDd29c326ba1c55);

    /// @notice Deposits the available balance of the underlying token into the strategy.
    ///         The strategy then uses the amount for yield-generating activities.
    ///         This can be called by either the keeper or governance.
    ///         Note that earn cannot be called when deposits are paused.
    /// @dev Pause is enforced at the Strategy level (this allows to still earn yield when the Vault is paused)
    function earn() external override {
        require(!pausedDeposit, "pausedDeposit"); // dev: deposits are paused, we don't earn as well
        _onlyAuthorizedActors();

        uint256 _bal = available();
        tokenProxy.safeTransfer(strategy, _bal);
        IStrategy(strategy).earn();
    }

    /// ===== Internal Implementations =====

    /// @notice Deposits `_amount` tokens, issuing shares to `recipient`. 
    ///         Note that deposits are not accepted when `pausedDeposit` is true. 
    /// @dev This is the actual deposit operation.
    ///      Deposits are based on the realized value of underlying assets between Sett & associated Strategy
    /// @param _recipient Address to issue the Sett shares to.
    /// @param _amount Quantity of tokens to deposit. 
    function _depositFor(address _recipient, uint256 _amount) internal override nonReentrant {
        require(_recipient != address(0), "Address 0");
        require(_amount != 0, "Amount 0");
        require(!pausedDeposit, "pausedDeposit"); // dev: deposits are paused

        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        tokenProxy.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _mintSharesFor(_recipient, _after.sub(_before), _pool);
    }

    /// @notice Redeems `_shares` for an appropriate amount of tokens.
    /// @dev This is the actual withdraw operation.
    ///      Withdraws from strategy positions if sett doesn't contain enough tokens to process the withdrawal. 
    ///      Calculates withdrawal fees and issues corresponding shares to treasury.
    ///      No rebalance implementation for lower fees and faster swaps
    /// @param _shares Quantity of shares to redeem. 
    function _withdraw(uint256 _shares) internal override nonReentrant {
        require(_shares != 0, "0 Shares");

        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint256 b = token.balanceOf(address(this));
        if (b < r) {
            uint256 _toWithdraw = r.sub(b);
            IStrategy(strategy).withdraw(_toWithdraw);
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _toWithdraw) {
                r = b.add(_diff);
            }
        }
        uint256 _fee = _calculateFee(r, withdrawalFee);

        // Send funds to user
        tokenProxy.safeTransfer(msg.sender, r.sub(_fee));

        // After you burned the shares, and you have sent the funds, adding here is equivalent to depositing
        // Process withdrawal fee
        if(_fee > 0) {
            _mintSharesFor(treasury, _fee, balance().sub(_fee));
        }
    }
}