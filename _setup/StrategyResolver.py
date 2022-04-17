from helpers.StrategyCoreResolver import StrategyCoreResolver
from rich.console import Console
from brownie import interface

console = Console()


class StrategyResolver(StrategyCoreResolver):
    def get_strategy_destinations(self):
        """
        Track balances for all strategy implementations
        (Strategy Must Implement)
        """
        sett = self.manager.sett
        strategy = self.manager.strategy
        return {
            "vester": strategy.vester(),
            "badgerTree": sett.badgerTree(),
        }

    def add_balances_snap(self, calls, entities):
        super().add_balances_snap(calls, entities)
        strategy = self.manager.strategy

        gmx = interface.IERC20(strategy.GMX_ADDRESS())
        esGmx = interface.IERC20(strategy.ES_GMX_ADDRESS())
        weth = interface.IERC20(strategy.WETH_ADDRESS())

        calls = self.add_entity_balances_for_tokens(calls, "gmx", gmx, entities)
        calls = self.add_entity_balances_for_tokens(calls, "esGmx", esGmx, entities)
        calls = self.add_entity_balances_for_tokens(calls, "weth", weth, entities)

        return calls

    def hook_after_confirm_withdraw(self, before, after, params):
        """
        Specifies extra check for ordinary operation on withdrawal
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def hook_after_confirm_deposit(self, before, after, params):
        """
        Specifies extra check for ordinary operation on deposit
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True  ## Done in earn

    def hook_after_earn(self, before, after, params):
        """
        Specifies extra check for ordinary operation on earn
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def confirm_harvest(self, before, after, tx):
        console.print("=== Compare Harvest ===")
        self.manager.printCompare(before, after)
        self.confirm_harvest_state(before, after, tx)

        super().confirm_harvest(before, after, tx)

        strategy = self.manager.strategy

        harvests = []

        try: 
            harvests = tx.events["Harvested"]
        except:
            print("No Harvests")

        # Harvests not required
        if harvests:
            assert len(harvests) == 1

            if len(tx.events["Harvested"]) == 1:
                event = tx.events["Harvested"][0]

                assert event["token"] == strategy.want()
                if event["amount"] > 0:
                    assert event["amount"] == after.get("sett.balance") - before.get("sett.balance")

                    valueGained = after.get("sett.getPricePerFullShare") > before.get(
                        "sett.getPricePerFullShare"
                    )
                    assert valueGained

                    if before.get("sett.performanceFeeGovernance") > 0:
                        assert after.balances("sett", "treasury") > before.balances(
                            "sett", "treasury"
                        )

                    if before.get("sett.performanceFeeStrategist") > 0:
                        assert after.balances("sett", "strategist") > before.balances(
                            "sett", "strategist"
                        )

        assert len(tx.events["TreeDistribution"]) == 1
        event = tx.events["TreeDistribution"][0]

        assert event["token"] == strategy.WETH()
        assert event["amount"] > 0

        if before.get("sett.performanceFeeGovernance") > 0:
            assert after.balances("weth", "treasury") > before.balances(
                "weth", "treasury"
            )

        if before.get("sett.performanceFeeStrategist") > 0:
            assert after.balances("weth", "strategist") > before.balances(
                "weth", "strategist"
            )

        # Assert no tokens left behind
        assert after.balances("weth", "strategy") == 0
        assert after.balances("esGmx", "strategy") == 0
        assert after.balances("gmx", "strategy") == 0

    def confirm_tend(self, before, after, tx):
        assert True
