import os
import subprocess

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
from rl_tools.rl.WandbWrapper import WandbWrapper
from torch_files.GameNetwork import GameNetwork
from torch_files.callbacks import StrategyMetricsCallback
from torch_files.normalizers import make_normalizers

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


def main():
    args = RLArgsParser.parse_args()
    initializer = RLInitializer(args)
    tensorboard_proc = None
    wandb_run = None

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
        tensorboard_writer = None
        if not args.no_tensorboard:
            log_dir = f"{initializer.log_path}/tensorboard"
            tensorboard_writer = SummaryWriter(log_dir=log_dir)
            if args.tensorboard_port > 0:
                tensorboard_proc = subprocess.Popen(
                    [
                        "tensorboard",
                        "--logdir",
                        log_dir,
                        "--port",
                        str(args.tensorboard_port),
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                initializer.main_logger.info(
                    f"TensorBoard serving at http://localhost:{args.tensorboard_port}"
                )
        elif args.tensorboard_port > 0:
            initializer.main_logger.warning(
                "--tensorboard_port is ignored because --no_tensorboard is set"
            )
        if args.wandb_project:
            wandb_dir = os.path.abspath(initializer.log_path)
            os.makedirs(wandb_dir, exist_ok=True)
            tags = (
                [t.strip() for t in args.wandb_tags.split(",")]
                if args.wandb_tags
                else None
            )
            wrapper = WandbWrapper(
                project=args.wandb_project,
                rl_agent_params={
                    "gamma": 0.99,
                    "lam": 0.95,
                    "epochs": 5,
                    "batch_size": 64,
                    "rollout_size": 256,
                    "entropy_coef_start": 0.7,
                    "entropy_coef_end": 0.01,
                    "entropy_coef_decay_steps": 1_000_000,
                    "clip_epsilon": 0.2,
                    "value_loss_coef": 0.5,
                },
                optimizer_params={
                    "lr": 3e-4,
                },
                game_params={
                    "instances": args.instances,
                    "seed": args.seed,
                    "iterations": args.iterations,
                    "checkpoint": args.checkpoint,
                    "eval_every_timesteps": args.eval_every_timesteps,
                    "eval_instances": args.eval_instances,
                    "eval_episodes": args.eval_episodes,
                    "building_names": list(BUILDING_NAMES),
                    "no_obs_norm": args.no_obs_norm,
                    "no_reward_norm": args.no_reward_norm,
                },
                dir=wandb_dir,
                entity=args.wandb_entity,
                name=args.wandb_name or os.path.basename(initializer.log_path),
                tags=tags,
                mode=args.wandb_mode,
            )
            wandb_run = wrapper.init()
            initializer.main_logger.info(
                f"W&B run '{wandb_run.name}' ({args.wandb_mode}) id={wandb_run.id}, "
                f"dir={wandb_dir}"
            )
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
        observation_normalizer, reward_normalizer = make_normalizers(args, gamma=0.99)
        agent = PPOAgent(
            network=network,
            optimizer=optimizer,
            envs=envs,
            rollout_size=256,
            tensorboard_writer=tensorboard_writer,
            wandb=wandb_run,
            callback=callback,
            observation_normalizer=observation_normalizer,
            reward_normalizer=reward_normalizer,
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
        if wandb_run is not None:
            wandb_run.finish()
        if tensorboard_proc is not None:
            tensorboard_proc.terminate()
        initializer.stop_instances()


if __name__ == "__main__":
    main()
