import time

from brownie import (
    GlpBlueberryFarmer,
    TheVault,
    interface,
    accounts,
)
from _setup.config import (
    WANT, 
    WANT_PROXY,
    WHALE_ADDRESS,

    PERFORMANCE_FEE_GOVERNANCE,
    PERFORMANCE_FEE_STRATEGIST,
    WITHDRAWAL_FEE,
    MANAGEMENT_FEE,
)
from helpers.constants import MaxUint256
from rich.console import Console

console = Console()

from dotmap import DotMap
import pytest


## Accounts ##
@pytest.fixture
def deployer():
    return accounts[0]

@pytest.fixture
def user():
    return accounts[9]


## Fund the account
@pytest.fixture
def want(deployer):
    TOKEN_ADDRESS = WANT
    TOKEN_PROXY_ADDRESS = WANT_PROXY
    feeStakedGlp = interface.IERC20Detailed(TOKEN_ADDRESS)
    stakedGlp = interface.IERC20Detailed(TOKEN_PROXY_ADDRESS)
    WHALE = accounts.at(WHALE_ADDRESS, force=True) ## Address with tons of token

    stakedGlp.approve(deployer, feeStakedGlp.balanceOf(WHALE), {"from": WHALE})
    stakedGlp.transferFrom(WHALE, deployer, feeStakedGlp.balanceOf(WHALE) / 5, {"from": deployer})
    return feeStakedGlp

@pytest.fixture
def weth():
    return interface.IERC20Detailed('0x82af49447d8a07e3bd95bd0d56f35241523fbab1');

@pytest.fixture
def wantProxy():
    TOKEN_PROXY_ADDRESS = WANT_PROXY
    return interface.IERC20Detailed(TOKEN_PROXY_ADDRESS)

@pytest.fixture
def strategist():
    return accounts[1]


@pytest.fixture
def keeper():
    return accounts[2]


@pytest.fixture
def guardian():
    return accounts[3]


@pytest.fixture
def governance():
    return accounts[4]

@pytest.fixture
def treasury():
    return accounts[5]


@pytest.fixture
def proxyAdmin():
    return accounts[6]


@pytest.fixture
def randomUser():
    return accounts[7]

@pytest.fixture
def badgerTree():
    return accounts[8]



@pytest.fixture
def deployed(want, deployer, strategist, keeper, guardian, governance, proxyAdmin, randomUser, badgerTree):
    """
    Deploys, vault and test strategy, mock token and wires them up.
    """
    want = want


    vault = TheVault.deploy({"from": deployer})
    vault.initialize(
        want,
        governance,
        keeper,
        guardian,
        governance,
        strategist,
        badgerTree,
        "",
        "",
        [
            PERFORMANCE_FEE_GOVERNANCE,
            PERFORMANCE_FEE_STRATEGIST,
            WITHDRAWAL_FEE,
            MANAGEMENT_FEE,
        ],
    )
    vault.setStrategist(deployer, {"from": governance})
    # NOTE: TheVault starts unpaused

    # address public constant SWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    # address public constant SWAP_QUOTER_ADDRESS = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    strategy = GlpBlueberryFarmer.deploy({"from": deployer})
    strategy.initialize(vault, ['0xE592427A0AEce92De3Edee1F18E0157C05861564', '0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6'])
    # NOTE: Strategy starts unpaused

    vault.setStrategy(strategy, {"from": governance})

    return DotMap(
        deployer=deployer,
        vault=vault,
        strategy=strategy,
        want=want,
        governance=governance,
        proxyAdmin=proxyAdmin,
        randomUser=randomUser,
        performanceFeeGovernance=PERFORMANCE_FEE_GOVERNANCE,
        performanceFeeStrategist=PERFORMANCE_FEE_STRATEGIST,
        withdrawalFee=WITHDRAWAL_FEE,
        managementFee=MANAGEMENT_FEE,
        badgerTree=badgerTree
    )


## Contracts ##
@pytest.fixture
def vault(deployed):
    return deployed.vault


@pytest.fixture
def strategy(deployed):
    return deployed.strategy



@pytest.fixture
def tokens(deployed):
    return [deployed.want]

### Fees ###
@pytest.fixture
def performanceFeeGovernance(deployed):
    return deployed.performanceFeeGovernance


@pytest.fixture
def performanceFeeStrategist(deployed):
    return deployed.performanceFeeStrategist


@pytest.fixture
def withdrawalFee(deployed):
    return deployed.withdrawalFee


@pytest.fixture
def setup_share_math(deployer, vault, want, governance):

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0
    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    vault.earn({"from": governance})

    return DotMap(depositAmount=depositAmount)


## Forces reset before each test
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass
