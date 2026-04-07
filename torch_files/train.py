import torch

from rl_tools.game_engine.GameEnvConnector import GameEnvConnector
from rl_tools.game_engine.HeadlessGameEngine.HeadlessGameEngineFactory import (
    HeadlessGameEngineFactory,
)
from rl_tools.rl.RLArgsParser import RLArgsParser
from rl_tools.rl.RLInitializer import RLInitializer
from rl_tools.rl.RLAgent.PolicyGradientAgent.PPOAgent import PPOAgent
from torch_files.GameNetwork import GameNetwork


def main():
    args = RLArgsParser.parse_args()
    initializer = RLInitializer(args)

    try:
        connectors = initializer.start_instances()

        from rl_tools.rl.Environment.Environment import Environment
        envs = [Environment(connector) for connector in connectors]

        network = GameNetwork(n_cells=192, cell_features=5, n_global_features=3, n_buildings=10, n_cells_out=192)
        optimizer = torch.optim.Adam(network.parameters(), lr=3e-4)
        agent = PPOAgent(network=network, optimizer=optimizer, envs=envs)
        agent.train(iterations=1000)

    except KeyboardInterrupt:
        initializer.main_logger.info("Interrupted — shutting down...")
    except Exception as e:
        initializer.main_logger.error(f"Fatal error: {e}", exc_info=True)
    finally:
        initializer.stop_instances()


if __name__ == "__main__":
    main()
