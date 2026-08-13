from __future__ import annotations

from rl_tools.rl.Factory import NetworkFactory
from torch_files.GameNetwork import GameNetwork

# Must match Godot ResourceDatabase recursive .tres load order under resources/buildings/
BUILDING_NAMES = (
    "CityCenter",
    "Housing",
    "Farm",
    "StoneWorks",
    "TimberYard",
    "Mine",
    "Sawmill",
    "Dock",
    "TownHall",
    "Workshop",
)


class StrategyNetworkFactory(NetworkFactory):
    _instance: "StrategyNetworkFactory | None" = None

    def __new__(cls) -> "StrategyNetworkFactory":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    @classmethod
    def instance(cls) -> "StrategyNetworkFactory":
        return cls()

    @property
    def building_names(self):
        return BUILDING_NAMES

    def build(self):
        return GameNetwork(
            n_cell_features=7,
            n_global_features=15,
            n_buildings=len(BUILDING_NAMES),
            n_builder_features=6,
            d_model=128,
            n_heads=4,
            grid_h=12,
            grid_w=16,
            build_spatial_ch=64,
            build_cond_ch=16,
            entropy_weights={
                "action": 1.0,
                "builder": 0.3,
                "building": 0.3,
                "move_cell": 0.1,
                "build_cell": 0.1,
            },
        )
