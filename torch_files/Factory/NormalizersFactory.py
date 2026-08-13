from __future__ import annotations

from rl_tools.rl.Factory import NormalizersFactory
from torch_files.normalizers import make_normalizers


class StrategyNormalizersFactory(NormalizersFactory):
    _instance: "StrategyNormalizersFactory | None" = None

    def __new__(cls) -> "StrategyNormalizersFactory":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    @classmethod
    def instance(cls) -> "StrategyNormalizersFactory":
        return cls()

    def build(self, args):
        return make_normalizers(args, gamma=0.99)
