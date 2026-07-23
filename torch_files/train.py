import torch

from torch.utils.tensorboard.writer import SummaryWriter
from rl_tools.rl.Callback import CallbackList
from rl_tools.rl.Callback.EvalCallback import EvalCallback
from rl_tools.rl.Callback.NetworkSaveCallback import NetworkSaveCallback
from rl_tools.rl.Callback.StopTrainingCallback.KeyStopCallback import KeyStopCallback
from rl_tools.rl.Callback.TimingCallback import TimingCallback
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
        connectors = initializer.start_instances(
            n=args.instances,
            id_offset=0,
            render=args.render,
            role="train",
        )

        from rl_tools.rl.Environment.Environment import Environment

        envs = [
            Environment(
                connector,
                seed_mode="train",
                seed_base=args.seed,
                env_index=i,
                n_parallel=args.instances,
            )
            for i, connector in enumerate(connectors)
        ]

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
        callbacks = [
            StrategyMetricsCallback(building_names=BUILDING_NAMES, n_builders=5),
            TimingCallback(),
        ]
        if args.eval_every_timesteps:
            if args.eval_instances < 1:
                raise ValueError("--eval_instances must be >= 1 when eval is enabled")
            if args.eval_episodes < 1:
                raise ValueError("--eval_episodes must be >= 1 when eval is enabled")
            eval_connectors = initializer.start_instances(
                n=args.eval_instances,
                id_offset=args.instances,
                render=args.render or args.render_eval,
                role="eval",
            )
            eval_envs = [
                Environment(
                    connector,
                    seed_mode="eval",
                    env_index=j,
                    n_parallel=args.eval_instances,
                )
                for j, connector in enumerate(eval_connectors)
            ]
            callbacks.append(
                EvalCallback(
                    envs=eval_envs,
                    every_timesteps=args.eval_every_timesteps,
                    n_episodes=args.eval_episodes,
                )
            )
        callbacks.extend(
            [
                KeyStopCallback(key="q"),
                NetworkSaveCallback(
                    save_path=f"{initializer.log_path}/checkpoints/final.pt",
                    save_every_updates=args.save_every_updates,
                ),
            ]
        )
        callback = CallbackList(callbacks)
        agent = PPOAgent(
            network=network,
            optimizer=optimizer,
            envs=envs,
            rollout_size=64,
            tensorboard_writer=summary_writer,
            callback=callback,
        )
        if args.checkpoint:
            agent.load(
                args.checkpoint,
                load_optimizer=not args.no_load_optimizer,
                load_rng=not args.no_load_rng,
            )
        agent.train(iterations=args.iterations)

    except KeyboardInterrupt:
        initializer.main_logger.info("Interrupted — shutting down...")
    except Exception as e:
        initializer.main_logger.error(f"Fatal error: {e}", exc_info=True)
    finally:
        initializer.stop_instances()


if __name__ == "__main__":
    main()
