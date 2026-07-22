import torch

from torch.utils.tensorboard.writer import SummaryWriter
from rl_tools.rl.RLArgsParser import RLArgsParser
from rl_tools.rl.RLInitializer import RLInitializer
from rl_tools.rl.RLAgent.PolicyGradientAgent.PPOAgent import PPOAgent
from torch_files.GameNetwork import GameNetwork
from torch_files.callbacks import StrategyMetricsCallback

# Must match Godot ResourceDatabase recursive .tres load order under resources/buildings/
BUILDING_NAMES = (
    "CityCenter",
    "Housing",
    "Farm",
    "StoneWorks",
    "TimberYard",
    "Mine",
    "Sawmill",
    "Bridge",
    "TownHall",
)


def main():
    args = RLArgsParser.parse_args()
    initializer = RLInitializer(args)

    try:
        connectors = initializer.start_instances()

        from rl_tools.rl.Environment.Environment import Environment

        envs = [Environment(connector) for connector in connectors]

        network = GameNetwork(
            n_cell_features=5,
            n_global_features=15,
            n_buildings=len(BUILDING_NAMES),
            n_builder_features=5,
            d_model=128,
            n_heads=4,
            grid_h=12,
            grid_w=16,
            build_spatial_ch=64,
            build_cond_ch=16,
        )
        optimizer = torch.optim.Adam(network.parameters(), lr=3e-4)
        summary_writer = SummaryWriter(log_dir=f"{initializer.log_path}/tensorboard")
        callback = StrategyMetricsCallback(building_names=BUILDING_NAMES)
        agent = PPOAgent(
            network=network,
            optimizer=optimizer,
            envs=envs,
            rollout_size=64,
            tensorboard_writer=summary_writer,
            callback=callback,
        )
        agent.train(iterations=1000)

    except KeyboardInterrupt:
        initializer.main_logger.info("Interrupted — shutting down...")
    except Exception as e:
        initializer.main_logger.error(f"Fatal error: {e}", exc_info=True)
    finally:
        initializer.stop_instances()


if __name__ == "__main__":
    main()
