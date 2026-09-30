from pathlib import Path

import yaml

from rl_tools.rl.Evolution import BudgetSchedule, EvolutionOrchestrator
from rl_tools.rl.RLArgsParser import RLArgsParser
from torch_files.Evolution.StrategyEvolutionSpace import StrategyEvolutionSpace

CHILD_RUNNER_PATH = "torch_files.Evolution.StrategyChildRunner:StrategyChildRunner"


def _load_evo_cfg(config_path: str | None) -> dict:
    if not config_path:
        return {}
    data = yaml.safe_load(Path(config_path).read_text())
    if isinstance(data, dict):
        return data.get("evolution", {}) or {}
    return {}


def main():
    args = RLArgsParser.parse_args()
    evo_cfg = _load_evo_cfg(getattr(args, "config", None))
    space = StrategyEvolutionSpace.genome_space()
    budget = BudgetSchedule(
        start=evo_cfg.get("steps_start", 50000),
        end=evo_cfg.get("steps_end", 750000),
        curve=evo_cfg.get("steps_curve", "geometric"),
    )
    resume_dir = getattr(args, "resume_evolution", None)
    orchestrator = EvolutionOrchestrator(
        args,
        space,
        budget,
        CHILD_RUNNER_PATH,
        evo_cfg=evo_cfg,
        root_dir=resume_dir,
        resume=bool(resume_dir),
    )
    result = orchestrator.evolve()
    print(f"Evolution finished. Root: {orchestrator.root_dir}")
    print("Best genome:", result.get("best_genome"))
    print("Best fitness:", result.get("best_fitness"))


if __name__ == "__main__":
    main()
