from __future__ import annotations

from collections import Counter
from collections.abc import Sequence
from typing import Any

import numpy as np
import torch
from tensordict import TensorDict

from rl_tools.rl.Callback import Callback

ACTION_MOVE = 1
ACTION_BUILD = 2

DEFAULT_ACTION_TYPE_NAMES = ("next_turn", "move", "build")


class StrategyMetricsCallback(Callback):
    """Game-specific TB/W&B metrics for the hex strategy action layout.

    Action vector columns: [action_type, builder_id, building_type, cell_flat]
      - 0 next turn
      - 1 move (builder + cell)
      - 2 build (building + cell)
    """

    def __init__(
        self,
        *,
        building_names: Sequence[str],
        action_type_names: Sequence[str] | None = None,
        n_builders: int = 5,
    ) -> None:
        super().__init__()
        if n_builders <= 0:
            raise ValueError(f"n_builders must be positive, got {n_builders}")
        self.building_names = list(building_names)
        self.action_type_names = list(action_type_names or DEFAULT_ACTION_TYPE_NAMES)
        self.n_builders = n_builders

    def on_train_start(self) -> None:
        if self.agent is None:
            return
        if self.agent.tensorboard_writer is None:
            return
        builder_tags = [
            f"policy/builder_selection/builder_{i}" for i in range(self.n_builders)
        ]
        building_tags = [
            f"policy/building_selection/{name}" for name in self.building_names
        ]
        action_tags = [
            f"policy/action_selection/{name}" for name in self.action_type_names
        ]
        self.agent.tensorboard_writer.add_custom_scalars(
            {
                "Policy": {
                    "Building selection": ["Multiline", building_tags],
                    "Builder selection": ["Multiline", builder_tags],
                    "Action selection": ["Multiline", action_tags],
                }
            }
        )

    def on_train_end(self) -> None:
        pass

    def on_rollout_start(self) -> None:
        pass

    def on_step(
        self,
        *,
        actions: Any,
        rewards: Sequence[float],
        dones: Sequence[bool],
        infos: Sequence[dict],
    ) -> bool:
        return True

    def on_rollout_end(self, rollout: TensorDict) -> None:
        if self.agent is None:
            return

        rewards = self._to_numpy(rollout["rewards"])
        dones = self._to_numpy(rollout["dones"]).astype(bool)
        actions = self._to_numpy(rollout["actions"])

        self.agent.log("rollout/mean_reward", float(np.mean(rewards)))
        self.agent.log("rollout/done_rate", float(np.mean(dones)))
        self.agent.log(
            "rollout/mean_undiscounted_return",
            float(np.mean(np.sum(rewards, axis=0))),
        )

        if actions.ndim < 2:
            return

        flat_actions = actions.reshape(-1, actions.shape[-1])
        types = flat_actions[:, 0].astype(np.int64)

        type_counts = Counter(types.tolist())
        type_total = sum(type_counts.values()) or 1
        for action_id, name in enumerate(self.action_type_names):
            self.agent.log(
                f"policy/action_selection/{name}",
                type_counts[action_id] / type_total,
            )

        build_mask = types == ACTION_BUILD
        buildings = (
            flat_actions[build_mask, 2].astype(np.int64)
            if np.any(build_mask)
            else np.array([], dtype=np.int64)
        )
        building_counts = Counter(buildings.tolist())
        building_total = sum(building_counts.values()) or 1
        for building_id, name in enumerate(self.building_names):
            self.agent.log(
                f"policy/building_selection/{name}",
                building_counts[building_id] / building_total,
            )

        move_mask = types == ACTION_MOVE
        builders = (
            flat_actions[move_mask, 1].astype(np.int64)
            if np.any(move_mask)
            else np.array([], dtype=np.int64)
        )
        builder_counts = Counter(builders.tolist())
        builder_total = sum(builder_counts.values()) or 1
        for builder_id in range(self.n_builders):
            self.agent.log(
                f"policy/builder_selection/builder_{builder_id}",
                builder_counts[builder_id] / builder_total,
            )

    def on_update_start(self, rollout: TensorDict) -> None:
        if self.agent is None:
            return
        if "returns" in rollout:
            returns = self._to_numpy(rollout["returns"])
            self.agent.log("rollout/mean_return", float(np.mean(returns)))
        if "advantages" in rollout:
            advantages = self._to_numpy(rollout["advantages"])
            self.agent.log("rollout/mean_advantage", float(np.mean(advantages)))

    def on_update_end(self, update_info: dict) -> None:
        pass

    @staticmethod
    def _to_numpy(values: Any) -> np.ndarray:
        if isinstance(values, torch.Tensor):
            return values.detach().cpu().numpy()
        return np.asarray(values)
