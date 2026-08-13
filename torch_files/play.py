import argparse
from concurrent.futures import ThreadPoolExecutor
import sys

import numpy as np
import torch
from rl_tools.game_engine.HeadlessGameEngine import HeadlessGameEngine
from rl_tools.rl.Environment import Environment
from rl_tools.rl.RLInitializer import RLInitializer
from rl_tools.rl.Trainer import _seed_rng
from torch_files.Factory import (
    StrategyNetworkFactory,
    StrategyNormalizersFactory,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a saved RL agent without training."
    )
    parser.add_argument(
        "--checkpoint",
        required=True,
        type=str,
        help="Path to checkpoint .pt file",
    )
    parser.add_argument(
        "--episodes", type=int, default=5, help="Number of episodes to run"
    )
    parser.add_argument(
        "--instances",
        type=int,
        default=1,
        help="Number of parallel Godot environments",
    )
    parser.add_argument(
        "--render",
        action="store_true",
        help="Show Godot windows",
    )
    parser.add_argument(
        "--deterministic",
        action="store_true",
        default=True,
        help="Use argmax (greedy) actions",
    )
    parser.add_argument(
        "--no-deterministic",
        action="store_false",
        dest="deterministic",
        help="Use stochastic sampled actions",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Seeds torch/numpy/python RNG and map seed base (negative values = eval-style seeding)",
    )
    parser.add_argument(
        "--max_steps",
        type=int,
        default=10_000,
        help="Maximum steps per episode",
    )
    parser.add_argument(
        "--log_level",
        type=str,
        default="INFO",
        choices=["TRACE", "DEBUG", "INFO", "WARNING", "ERROR"],
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Only print ERROR logs to console and files; metrics go to TensorBoard only",
    )
    parser.add_argument(
        "--log_to_file",
        action="store_true",
        help="Enable Godot log-to-file",
    )
    parser.add_argument(
        "-k",
        "--kill_existing",
        action="store_true",
        help="Kill existing Godot headless instances before starting",
    )
    return parser.parse_args()


def _step_env(env: Environment, action: np.ndarray) -> tuple[dict, float, bool, dict]:
    o, r, d, info = env.step(action)
    if d:
        o = env.reset()
    return o, r, d, info if info is not None else {}


def main() -> None:
    args = parse_args()
    args.game_engine_type = HeadlessGameEngine.GameEngineType.GODOT
    _seed_rng(args.seed)

    initializer = RLInitializer(args)
    log = initializer.main_logger

    pool: ThreadPoolExecutor | None = None
    try:
        connectors = initializer.start_instances(
            n=args.instances,
            id_offset=0,
            render=args.render,
            role="eval",
        )

        envs = [
            Environment(
                connector,
                seed_mode="eval",
                seed_base=args.seed,
                env_index=i,
                n_parallel=args.instances,
            )
            for i, connector in enumerate(connectors)
        ]

        network = StrategyNetworkFactory.instance().build()

        from rl_tools.rl.RLAgent.PolicyGradientAgent.PPOAgent import PPOAgent

        observation_normalizer, reward_normalizer = (
            StrategyNormalizersFactory.instance().build(args)
        )
        agent = PPOAgent(
            network=network,
            envs=envs,
            observation_normalizer=observation_normalizer,
            reward_normalizer=reward_normalizer,
        )
        agent.load(args.checkpoint, load_optimizer=False, load_rng=False)
        agent.set_eval_mode(True)
        agent.network.deterministic = args.deterministic

        n_envs = len(envs)
        n_episodes = args.episodes
        max_steps = args.max_steps

        raw_obs = []
        for env in envs:
            env.episode_index = 0
            raw_obs.append(env.reset(restart_sequence=True))
        current_obs = [agent.split_observation(o) for o in raw_obs]

        ep_returns = [0.0] * n_envs
        ep_lengths = [0] * n_envs
        completed_returns: list[tuple[float, int]] = []
        completed_wins: list[bool] = []
        completed_infos: list[dict] = []

        pool = ThreadPoolExecutor(max_workers=n_envs)

        while len(completed_returns) < n_episodes:
            batch_obs = torch.stack(current_obs)
            forward = agent.get_action(batch_obs)
            actions = [
                forward["action"][i].detach().cpu().numpy() for i in range(n_envs)
            ]

            results = list(pool.map(_step_env, envs, actions))

            next_raw_obs: list[dict] = []
            for i, (o, r, d, info) in enumerate(results):
                if len(completed_returns) >= n_episodes:
                    break
                ep_returns[i] += float(r)
                ep_lengths[i] += 1
                finished = bool(d) or ep_lengths[i] >= max_steps
                if finished:
                    won = bool(info.get("won", False))
                    completed_returns.append((ep_returns[i], ep_lengths[i]))
                    completed_wins.append(won)
                    completed_infos.append(info if info is not None else {})
                    log.info(
                        f"Episode {len(completed_returns)}/{n_episodes}: "
                        f"{'WON' if won else 'LOST'} "
                        f"return={ep_returns[i]:.2f}  length={ep_lengths[i]}"
                        + (
                            f"  turns={info.get('turns', '?')}"
                            f"  completed={info.get('buildings_completed', {})}"
                            f"  pop={info.get('population', '?')}/{info.get('working_population', '?')}"
                            if info.get("reward_breakdown")
                            else ""
                        )
                    )
                    ep_returns[i] = 0.0
                    ep_lengths[i] = 0
                    if not d:
                        o = envs[i].reset()
                next_raw_obs.append(o)

            current_obs = [agent.split_observation(o) for o in next_raw_obs]

        returns_arr = np.asarray([r for r, _ in completed_returns])
        lengths_arr = np.asarray([l for _, l in completed_returns])
        n_wins = int(sum(completed_wins))
        n_eps = len(completed_returns)
        summary = (
            f"Results ({n_eps} episodes): "
            f"win rate={n_wins / n_eps:.0%} ({n_wins}/{n_eps}), "
            f"mean return={returns_arr.mean():.2f} +/- {returns_arr.std():.2f}, "
            f"mean length={lengths_arr.mean():.1f} +/- {lengths_arr.std():.1f}"
        )

        valid = [info for info in completed_infos if info.get("reward_breakdown")]
        if valid:
            win_turns = [float(info["turns"]) for info in valid if info.get("won")]
            loss_turns = [float(info["turns"]) for info in valid if info.get("lost")]
            completed_total = sum(
                (info.get("buildings_completed") or {}).values() for info in valid
            )
            mean_production = np.mean(
                [sum(info.get("production", []) or []) for info in valid]
            )
            summary += (
                (f", mean win turns={np.mean(win_turns):.1f}" if win_turns else "")
                + (f", mean loss turns={np.mean(loss_turns):.1f}" if loss_turns else "")
                + (f", mean buildings completed={completed_total / len(valid):.1f}")
                + (f", mean end production={mean_production:.1f}")
            )
        log.info(summary)

    except KeyboardInterrupt:
        initializer.main_logger.info("Interrupted — shutting down...")
    except Exception as e:
        initializer.main_logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
    finally:
        if pool is not None:
            pool.shutdown(wait=False)
        initializer.stop_instances()


if __name__ == "__main__":
    main()
