import torch

from torch.utils.tensorboard.writer import SummaryWriter
from rl_tools.rl.RLArgsParser import RLArgsParser
from rl_tools.rl.RLInitializer import RLInitializer
from rl_tools.rl.RLAgent.PolicyGradientAgent.PPOAgent import PPOAgent
from torch_files.GameNetwork import GameNetworkOld, GameNetwork


def main():
    args = RLArgsParser.parse_args()
    initializer = RLInitializer(args)

    try:
        connectors = initializer.start_instances()

        from rl_tools.rl.Environment.Environment import Environment
        envs = [Environment(connector) for connector in connectors]

        # network = GameNetworkOld(n_cells=192, cell_features=5, n_global_features=15, n_buildings=10, n_cells_out=192)
        network = GameNetwork(n_cell_features=5, n_global_features=15, n_buildings=9, n_builder_features=10, d_model=128, n_heads=4)
        optimizer = torch.optim.Adam(network.parameters(), lr=3e-4)
        summary_writer = SummaryWriter(log_dir="logs/tensorboard")
        agent = PPOAgent(network=network, optimizer=optimizer, envs=envs, rollout_size=64, tensorboard_writer=summary_writer)
        agent.train(iterations=1000)

    except KeyboardInterrupt:
        initializer.main_logger.info("Interrupted — shutting down...")
    except Exception as e:
        initializer.main_logger.error(f"Fatal error: {e}", exc_info=True)
    finally:
        initializer.stop_instances()


if __name__ == "__main__":
    main()
