from brownie import *
from helpers.constants import MaxUint256


def test_are_you_trying(deployer, vault, strategy, want, wantProxy, governance):
    """
    Verifies that you set up the Strategy properly
    """
    # Setup
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup

    # Deposit
    assert want.balanceOf(vault) == 0

    wantProxy.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    # ensure we can do multiple deposits 
    newDepositAmount = want.balanceOf(deployer) // 2
    depositAmount += newDepositAmount
    vault.deposit(newDepositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    chain.sleep(10000 * 13)  # Mine so we get past the cooldown period

    vault.earn({"from": governance})

    chain.sleep(10000 * 13)  # Mine so we get some interest

    ## TEST 1: Does the want get used in any way?
    assert want.balanceOf(vault) == depositAmount - available

    assert want.balanceOf(strategy) == depositAmount - want.balanceOf(vault)

    # Change to this if the strat is supposed to hodl and do nothing
    # assert strategy.balanceOf(want) = depositAmount

    ## TEST 2: Is the Harvest profitable?
    harvest = strategy.harvest({"from": governance})

    ## TEST 3: Does the strategy emit anything?
    event = harvest.events["TreeDistribution"]
    assert event["token"] == "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1" ## Add token you emit
    assert event["amount"] > 0 ## We want it to emit something
