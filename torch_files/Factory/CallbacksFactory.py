from __future__ import annotations

from rl_tools.rl.Factory import CallbacksFactory
from torch_files.callbacks import StrategyMetricsCallback

from torch_files.Factory.NetworkFactory import BUILDING_NAMES


class StrategyCallbacksFactory(CallbacksFactory):
    _instance: "StrategyCallbacksFactory | None" = None

    def __new__(cls) -> "StrategyCallbacksFactory":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    @classmethod
    def instance(cls) -> "StrategyCallbacksFactory":
        return cls()

    def build(self):
        return [StrategyMetricsCallback(building_names=BUILDING_NAMES, n_builders=5)]
