from __future__ import annotations

import argparse

from rl_tools.rl.Callback.StopTrainingCallback.MetricStopCallback import (
    MetricStopCallback,
)
from rl_tools.rl.Evolution import ChildRunner, ChildSpec
from rl_tools.rl.Trainer import Trainer
from torch_files.Evolution.StrategyEvolutionSpace import StrategyEvolutionSpace
from torch_files.Factory import (
    StrategyCallbacksFactory,
    StrategyExpertFactory,
    StrategyNetworkFactory,
    StrategyNormalizersFactory,
)
from torch_files.StrategyEvalCallback import StrategyEvalCallback
from torch_files.StrategyUDPObservation import StrategyUDPObservation


class StrategyChildRunner(ChildRunner):
    """Game-specific child runner: builds the strategy Trainer and wires the
    game's stopping callbacks (no-buildings gate + optional win-rate gate)."""

    observation_class = StrategyUDPObservation

    @classmethod
    def _configure(cls) -> None:
        import torch

        torch.set_num_threads(2)

    @classmethod
    def decode_genome(cls, genome: dict) -> ChildSpec:
        return StrategyEvolutionSpace.decode_genome(genome)

    @classmethod
    def build_trainer(cls, child_args: argparse.Namespace) -> Trainer:
        return Trainer(
            child_args,
            network_factory=StrategyNetworkFactory.instance(),
            callbacks_factory=StrategyCallbacksFactory.instance(),
            normalizers_factory=StrategyNormalizersFactory.instance(),
            expert_factory=StrategyExpertFactory.instance(),
            observation_class=StrategyUDPObservation,
            eval_callback_class=StrategyEvalCallback,
        )

    @classmethod
    def build_callbacks(cls, child_config: dict) -> list:
        callbacks = super().build_callbacks(child_config)
        callbacks.append(
            MetricStopCallback(
                metric="buildings_started",
                threshold=float(child_config.get("build_gate_threshold", 0.5)),
                patience=int(child_config.get("build_gate_patience", 3)),
                goal="below",
            )
        )
        win_rate_gate = float(child_config.get("win_rate_gate", 0.0))
        if win_rate_gate > 0:
            callbacks.append(
                MetricStopCallback(
                    metric="win_rate",
                    threshold=win_rate_gate,
                    patience=3,
                    goal="below",
                )
            )
        return callbacks
