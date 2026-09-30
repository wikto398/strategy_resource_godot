from __future__ import annotations

from typing import ClassVar

from rl_tools.rl.Evolution import ChildSpec, GeneSpec, GenomeSpace


class StrategyEvolutionSpace:
    """Gene space for the hex strategy game.

    Agent keys go to ``PPOAgent`` kwargs (via ``run(overrides)``), expert keys
    to ``args.expert_eps`` / ``expert_eps_decay_steps``, and everything else
    (reward coefficients + milestone threshold lists) to Godot ``engine_args``.
    """

    GENES: ClassVar[dict[str, GeneSpec]] = {
        "lr": GeneSpec(type="log_float", min=1e-6, max=1e-3),
        "gamma": GeneSpec(type="float", min=0.90, max=0.999),
        "lam": GeneSpec(type="float", min=0.85, max=0.995),
        "epochs": GeneSpec(type="int", min=3, max=10),
        "batch_size": GeneSpec(type="int", min=32, max=256),
        "entropy_coef_start": GeneSpec(type="float", min=0.01, max=0.4),
        "clip_epsilon": GeneSpec(type="float", min=0.1, max=0.3),
        "economy_coef": GeneSpec(type="float", min=0.005, max=0.1),
        "balance_coef": GeneSpec(type="float", min=0.0, max=0.3),
        "time_penalty": GeneSpec(type="float", min=-0.02, max=-0.001),
        "deficit_coef": GeneSpec(type="float", min=0.0, max=0.05),
        "over_commit_penalty": GeneSpec(type="float", min=0.0, max=1.0),
        "progress_building_coef": GeneSpec(type="float", min=0.0, max=0.5),
        "productive_bonus": GeneSpec(type="float", min=0.0, max=0.3),
        "pop_milestones": GeneSpec(type="list_ints", length=4, min=4, max=40, step=2),
        "prod_milestones": GeneSpec(
            type="list_ints", length=4, min=10, max=120, step=5
        ),
        "stock_milestones": GeneSpec(
            type="list_ints", length=3, min=800, max=3000, step=100
        ),
        "expert_eps": GeneSpec(type="choice", values=[0.0, 0.4]),
        "expert_eps_decay_steps": GeneSpec(type="choice", values=[0, 200000]),
    }

    AGENT_KEYS: ClassVar[set[str]] = {
        "lr",
        "gamma",
        "lam",
        "epochs",
        "batch_size",
        "entropy_coef_start",
        "clip_epsilon",
    }
    EXPERT_KEYS: ClassVar[set[str]] = {"expert_eps", "expert_eps_decay_steps"}

    @classmethod
    def genome_space(cls) -> GenomeSpace:
        return GenomeSpace(cls.GENES)

    @classmethod
    def decode_genome(cls, genome: dict) -> ChildSpec:
        agent = {k: genome[k] for k in cls.AGENT_KEYS if k in genome}
        engine: dict = {}
        for key, value in genome.items():
            if key in cls.AGENT_KEYS or key in cls.EXPERT_KEYS:
                continue
            if isinstance(value, list):
                engine[key] = ",".join(str(int(v)) for v in value)
            else:
                engine[key] = value
        return ChildSpec(
            agent_overrides=agent,
            engine_args=engine,
            expert_eps=float(genome.get("expert_eps", 0.0)),
            expert_eps_decay_steps=int(genome.get("expert_eps_decay_steps", 0)),
        )
