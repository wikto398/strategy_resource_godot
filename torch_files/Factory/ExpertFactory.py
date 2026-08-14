from __future__ import annotations

from rl_tools.rl.Factory import ExpertFactory
from torch_files.Expert import StrategyExpert


class StrategyExpertFactory(ExpertFactory):
    _instance: StrategyExpertFactory | None = None

    def __new__(cls) -> StrategyExpertFactory:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    @classmethod
    def instance(cls) -> StrategyExpertFactory:
        return cls()

    def build(self, args):
        return StrategyExpert()
