from __future__ import annotations

import numpy as np

from rl_tools.rl.Callback.EvalCallback import EvalCallback


class StrategyEvalCallback(EvalCallback):
    """Game-specific eval extension: aggregates the strategy episode summary.

    Terminal episodes carry a ``reward_breakdown`` dict plus ``population``,
    ``working_population``, ``total_resources``, ``production`` and
    ``buildings_started`` / ``buildings_completed`` in their ``info``. This
    subclass logs those (``eval/breakdown/*``, ``eval/buildings_*``,
    ``eval/mean_win_turns`` / ``mean_loss_turns``, ``eval/mean_end_*``) and
    extends ``eval/latest`` with the end-of-episode game state.
    """

    def _log_episode_summary(self, infos, step, log):
        # Truncated episodes carry no reward_breakdown -> not terminal.
        valid = [info for info in infos if info.get("reward_breakdown")]
        if not valid:
            return None
        n_valid = len(valid)

        win_turns = [
            float(info[self.turns_key])
            for info in valid
            if info.get(self.won_key) and info.get(self.turns_key) is not None
        ]
        loss_turns = [
            float(info[self.turns_key])
            for info in valid
            if info.get(self.lost_key) and info.get(self.turns_key) is not None
        ]
        if win_turns:
            log("mean_win_turns", np.mean(win_turns))
        if loss_turns:
            log("mean_loss_turns", np.mean(loss_turns))

        breakdown_totals: dict[str, float] = {}
        for info in valid:
            for key, value in info.get("reward_breakdown", {}).items():
                breakdown_totals[key] = breakdown_totals.get(key, 0.0) + float(value)
        for key, value in sorted(breakdown_totals.items()):
            log(f"breakdown/{key}", value / n_valid)

        for field in ("buildings_started", "buildings_completed"):
            totals: dict[str, float] = {}
            for info in valid:
                for key, value in info.get(field, {}).items():
                    totals[key] = totals.get(key, 0.0) + float(value)
            for key, value in sorted(totals.items()):
                log(f"{field}/{key}", value / n_valid)

        population = [float(info.get("population", 0.0)) for info in valid]
        working_population = [
            float(info.get("working_population", 0.0)) for info in valid
        ]
        total_resources = [float(info.get("total_resources", 0.0)) for info in valid]
        production = [float(sum(info.get("production", []) or [])) for info in valid]

        def _non_cc_total(field: str) -> list[float]:
            counts = []
            for info in valid:
                building_counts = info.get(field, {}) or {}
                total = sum(
                    float(v)
                    for name, v in building_counts.items()
                    if name != "City Center"
                )
                counts.append(total)
            return counts

        summary = {
            "mean_end_population": float(np.mean(population)),
            "mean_end_working_population": float(np.mean(working_population)),
            "mean_end_total_resources": float(np.mean(total_resources)),
            "mean_end_production": float(np.mean(production)),
            "buildings_started": float(np.mean(_non_cc_total("buildings_started"))),
            "buildings_completed": float(np.mean(_non_cc_total("buildings_completed"))),
        }
        for key, value in summary.items():
            log(key, value)
        return summary
