from __future__ import annotations

import argparse

from rl_tools.game_engine.ObservationNormalizer import (
    RunningMeanStdObservationNormalizer,
)
from rl_tools.game_engine.RewardNormalizer import (
    RunningMeanStdRewardNormalizer,
)


def make_normalizers(
    args: argparse.Namespace,
    *,
    gamma: float = 0.99,
) -> tuple[
    RunningMeanStdObservationNormalizer | None,
    RunningMeanStdRewardNormalizer | None,
]:
    """Build the game's normalizers, matching the default PPO gamma.

    Both are on by default and disabled via ``--no_obs_norm`` /
    ``--no_reward_norm``. Constructed identically in train.py and play.py so
    checkpointed normalizer state restores in both.
    """
    observation_normalizer = (
        None
        if getattr(args, "no_obs_norm", False)
        else RunningMeanStdObservationNormalizer()
    )
    reward_normalizer = (
        None
        if getattr(args, "no_reward_norm", False)
        else RunningMeanStdRewardNormalizer(gamma=gamma)
    )
    return observation_normalizer, reward_normalizer
