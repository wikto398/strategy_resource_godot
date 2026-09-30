"""Thin, game-specific wrapper over the generic evolution CLI.

The framework entrypoint is ``python -m rl_tools.rl.Evolution``; this module just
supplies the hex-strategy game's genome space and child runner so callers keep
using ``python -m torch_files.evolution``.

Equivalent generic invocation:

    python -m rl_tools.rl.Evolution \
        --space torch_files.Evolution.StrategyEvolutionSpace:StrategyEvolutionSpace \
        --child_runner torch_files.Evolution.StrategyChildRunner:StrategyChildRunner \
        --config torch_files/evolution.yaml
"""

from rl_tools.rl.Evolution.cli import run_evolution

SPACE_SPEC = "torch_files.Evolution.StrategyEvolutionSpace:StrategyEvolutionSpace"
CHILD_RUNNER_SPEC = "torch_files.Evolution.StrategyChildRunner:StrategyChildRunner"


def main():
    return run_evolution(space_spec=SPACE_SPEC, child_runner_spec=CHILD_RUNNER_SPEC)


if __name__ == "__main__":
    main()
