# Reward function

Implemented in `modules/ObservationCollector/ObservationCollector.gd`, computed once per
step (each action). Building/event bonuses are emitted through
`Global.add_to_reward(value, tag)` (tags: `build_start`, `build_finish`, `first_build`,
or the default `events`).

## Per-step reward

The reward is dispatched on the action that was just executed (tracked via
`ActionExecutor.action_executed` -> `last_action`).

| Step | Reward |
|---|---|
| Episode ended (`done`) | `_result_score()` terminal reward (below) |
| Bootstrap observation (no action yet) | `0` |
| **Next turn** (action type `0`) | all next-turn components below |
| **Move** (action type `1`) | `move` |
| **Build** (action type `2`) | `build` |
| + tagged events | building start/finish/first-of-type bonuses emitted during the action |

### Next-turn components

| Component | Formula | Constants |
|---|---|---|
| `skip` | `_skip_reward()` | `-0.02` (`skip_penalty`) |
| `time` | `_time_penalty()` | `-0.005` (`time_penalty`) |
| `deficit` | `_deficit_penalty()` | `-0.015 * min(5, deficit_duration)` per resource with `town_resources[r] <= 0` |
| `production` | `_production_penalty()` | `-0.01 * min(10, \|net_production\|)` per resource with `current_production[r] <= 0` **and** `town_resources[r] <= 0` **and no in-progress producer for `r`** — only a resource actually banked negative *and* with nothing being built about it is penalized; a healthy-stock buildout (or a negative net with full stock) is exempt |
| `surplus` | `_surplus_penalty()` | `-0.05 * min(10, net_r - 10)` per resource with `current_production[r] > 10` **and** `town_resources[r] > max(min_stock * 2, 2000)` — anti-spam: penalizes hoarding one resource far ahead of the others *and* past the Workshop cost (2+ Mines racing stone to thousands). Relative (ratio) + absolute (floor) gate means healthy saving/buildout is never penalized (`surplus` stays 0 on a winning line) |
| `economy` | `_economy_reward()` | `+0.05 * Σ clamp(net_production_r, 0, 10)` — **positives-only**: negatives are ignored here because they are already penalized by `production`/`deficit`; capping the negative side prevents the buildout phase (upkeep at start, production at completion) from being double-counted and making construction lose to inaction. 3-Mine spam drops from `+0.90` to `+0.05`/turn while a balanced 1-of-each economy (`+2.0`/turn) is untouched |
| `balance` | `_balance_reward()` | `+0.2` per resource with positive net production (max `+0.8` when all 4 positive) |
| `stock_warning` | `_stock_warning()` | `-0.02 * min(3, max(0, 1 - stock_r/100))` per resource |
| `milestones` | `_milestones()` | pop [4,5,6,8] -> +1.5 each; net prod [5,10,20,30] -> +1.0 each; `+0.02` per unit of **min-stock** growth (bottleneck resource) — rewards balanced saving, pays nothing for hoarding one resource to the cap |
| `stockpile` | `_stockpile_reward()` | per-resource min stock crossing [800,1200,1500] -> +1.0 each (aligns with Workshop win cost) |
| `productive` | `_productive_turn()` | `+0.3` if any builder is `building` or net production > 0 — **gated off** when at the population ceiling with no positive net production |
| `construction` | `_construction_reward()` | `+0.2` per progress point gained this turn (stalled buildings — no free population working them — earn `0`; reward is bounded by `build_time` total) |
| `win_progress` | `_win_progress()` | potential-based: `Φ = 0.005 * Σ completed build cost`, reward `γ*Φ(t) - Φ(t-1)` |
| `over_commit_state` | `_over_commit_state_penalty()` | `-0.10 * overshoot` per turn while `in_progress_buildings > free_population` — persists for every next-turn step until the over-commit is resolved |

All next-turn components fire once per turn (on the next-turn action), not on every action
within a turn. Net production already accounts for upkeep.

### Move

| Case | Reward |
|---|---|
| Destination field has an in-progress building | `+0.2` |
| Destination is buildable for any affordable building | `+0.1` |
| Otherwise | `0` |

### Build

| Case | Reward |
|---|---|
| Build action itself | `0` |
| Over-commit (starting any building while `in_progress_buildings > free_population`) | `-over_commit_penalty * overshoot` (`over_commit`), where `overshoot = in_progress - free_population` — scales with how far over the limit the start goes (3 extras cost `-0.75` with coef `0.25`) |
| + tagged events | building start/finish/first-of-type bonuses emitted during the action |

### Events

| Tag | Source | Reward |
|---|---|---|
| `build_start` | `ProductionHandler.start_production` | `+min(2.0, build_start_coef * total_build_cost / 100)` — coef `0.1`, deliberately small so starting buildings pays little |
| `build_finish` | production buildings | `+build_finish_coef * production_rate / (1 + count_of_type_completed)` — coef `0.15` (first completion `+3.0`, diminishing, anti single-type spam) |
| `build_finish` | non-production buildings (Housing, Dock, …) | `+build_finish_flat / (1 + count_of_type_completed)` — flat `5.0` (diminishing) |
| `resource_gap` | production buildings | `+0.05 * clamp(GAP_TARGET - projected_production_of_produced_resource, 0, 10)` — `projected` = completed production + production of **all in-progress** buildings of that type. Up to `+0.5` when under-produced (net < 10), `0` once saturated. Counts in-progress so parallel spam fills the gap immediately (5 Mines in flight → projected ≥ 25 → 0 for every completion); a lone genuine build still earns the bonus |
| `first_build` | first completion of each building type | `+3.0` |
| `housing` | Housing (only while fully employed) | `+housing_coef * population_increase` — coef `1.0` |
| `events` (default) | Special (`+0.5`) | varies |

## Terminal reward

`_result_score()` (applied once, on the `done` step):

```
score = (+50 if won else -10)
      + production_bonus   (Σ current_production * production_bonus_coef, coef `0.3`)
      + progress_bonus     ((population + working_population) * 0.1)
```

## Observability

Per-step components are accumulated into `episode_components` and logged at
`INFO` when the episode ends:

```
Episode ended (WON|LOST). Reward breakdown: {"time": ..., "stock_warning": ..., ...}
```

Component keys: `time`, `deficit`, `production`, `surplus`, `economy`, `stock_warning`,
`milestones`, `stockpile`, `productive`, `construction`, `win_progress`,
`build_start`, `build_finish`, `first_build`, `events`, `move`, `skip`, `build`,
`over_commit`, `over_commit_state`, `balance`, `housing`, `resource_gap`, `terminal`.

The win/loss outcome is also shipped to the trainer via the observation message's
`info` dict (`{"won": is_game_won, "lost": done and not is_game_won}`), which drives
`eval/win_rate` / `eval/n_wins` in `EvalCallback` and win-rate reporting in `play.py`.

On the `done` step `info` additionally carries the full episode summary:
`turns`, `population`, `working_population`, `total_resources`, `production`
(per-resource net), `buildings_started` / `buildings_completed` (name -> count),
and `reward_breakdown` (per-episode sums of every component above). `EvalCallback`
aggregates these over eval episodes into `eval/mean_win_turns`,
`eval/mean_loss_turns`, `eval/breakdown/<component>`,
`eval/buildings_started/<name>`, `eval/buildings_completed/<name>`,
`eval/mean_end_population`, `eval/mean_end_working_population`,
`eval/mean_end_total_resources`, and `eval/mean_end_production`. The Godot log's
`Episode ended (...)` line shows the same summary.

## Tunable coefficients

All reward coefficients are plain vars on the `RewardConfig` autoload
(`globals/RewardConfig.gd`), defaulting to the values above. Override any of them
at launch via repeatable `--engine_args key=value` or the `engine_args:` section of
a `--config ...yaml` file (explicit CLI `--engine_args` win on key conflicts).
They are forwarded verbatim to every Godot instance (train + eval) and loaded once
by the autoload.

```bash
python -m torch_files.train --engine_args economy_coef=0.03 --engine_args surplus_coef=0.1 ...
# or, in torch_files/config.yaml:
# engine_args:
#   economy_coef: 0.03
#   surplus_coef: 0.1
```

Keys are snake_case matching the autoload var names: `economy_coef`, `economy_cap`,
`balance_coef`, `production_penalty_coef`, `production_penalty_cap`, `deficit_coef`,
`deficit_cap`, `gap_coef`, `gap_target`, `gap_cap`, `stock_warning_coef`,
`stock_warning_threshold`, `productive_bonus`, `construction_bonus`,
`first_build_bonus`, `win_progress_coef`, `over_commit_penalty`, `over_commit_state_penalty`,
`win_bonus`,
`loss_penalty`, `loss_survival_horizon`, `pop_milestone_bonus`, `stock_milestone_bonus`,
`gamma`, `peak_coef`, `build_start_coef`, `build_finish_coef`, `build_finish_flat`,
`housing_coef`, `skip_penalty`, `time_penalty`, `production_bonus_coef`,
and the `surplus_*` set
(`surplus_coef`, `surplus_target`, `surplus_stock_ratio`, `surplus_stock_floor`, `surplus_cap`).

## Notes

- `last_action` is set from the parsed action in `ActionExecutor`; the reward is
  computed on the next observation, so it reflects the effects of that action.
- Penalties/shaping fire once per turn (on the next-turn action), not per action.
- Milestone/peak state lives on the collector and resets with each episode (scene
  reload). Thresholds are chosen so they are not passed at game start (start pop is 3,
  start net production is 0, start stock is 800 per resource; stockpile milestones
  start at 800 so the agent must actually save, and prod milestones require positive
  net production).
- The over-commit penalty (`over_commit`) fires on the build action itself (not the
  next-turn action) when **any** building is started while
  `in_progress_buildings > free_population`, scaled by the degree of over-commit
  (`-over_commit_penalty * overshoot`). While still over-committed, an additional
  `over_commit_state` penalty (`-0.10 * overshoot`) fires on every next-turn action
  until it resolves. Together this stops the "start 18 buildings, complete 3" death
  spiral: with no Housing, population stays at 3, so at most 3 buildings can ever be
  under construction, extras stall forever while draining upkeep, and the scaling +
  persistent penalties make the state itself costly. Applies to Housing too (its
  4-resource upkeep drains with no production).
- The loss penalty is a **flat `-10`** on every loss — the previous
  `-10 * (1 - min(turn / loss_survival_horizon, 1))` scaling made any loss after turn
  200 cost `0`, so "spam cheap buildings for completion bonuses, survive past 200, die
  free" was a genuine local optimum. With a flat penalty a slow death is just as costly
  as a fast one, and `win_bonus` (+50) clearly dominates the per-step shaping terms.
- The buildout phase (upkeep applied at construction start, production only at
  completion) is **not double-counted**: `economy` is positives-only (negatives are
  ignored there) and `production` only penalizes a resource that is actually **banked
  negative** (`town_resources[r] <= 0`) *and* has **no in-progress producer** for it.
  Previously the penalties fired on negative net with full stock, which made any
  building trajectory (and even a healthy idle town's City-Center upkeep) worse than
  doing nothing — with a full-episode rollout the agent correctly converged to "refuse
  to build". Stalled over-committed construction is still caught by the
  `over_commit`/`over_commit_state` penalties, and `surplus`/`deficit`/the loss penalty
  still punish a collapsed economy.
- `production`/`deficit` penalties are moderate (`-0.02 * min(10,|net|)`,
  `-0.025 * min(5,duration)`) so that building — which applies upkeep at start but only
  produces at completion — is not overwhelmed by the temporary bleed. The `construction`
  component additionally credits every in-progress building each turn. The economy reward
  rewards positive net production (positives-only) and `balance` pays `+0.2` per positive
  resource, so a mixed/balanced economy earns more than single-type spam.
- Anti-spam: the `economy_cap` saturates the per-resource economy reward at one
  building's worth (`min(net, 10)`), the `milestones` peak bonus pays only on min-stock
  (bottleneck) growth, and `surplus` penalizes a resource banked far ahead of the
  minimum stock and past the Workshop cost. Together they make stacking 2+ Mines pay
  nothing extra while a balanced 1-of-each economy (all net `+6..13`, under every cap)
  keeps the full reward. `build_finish_coef` is kept at `0.15` so the completion bonus
  (`0.15 * production_rate` = `+3.0` for the first production building) never dwarfs the
  win bonus — when `production_rate` was doubled to 20 the old `0.7` coef made the first
  completion worth `+14`, which made mine-spam a reward-hacking local optimum.
- Production rates (defined in `resources/buildings/production/*/*.tres`, upkeep
  unchanged): Farm/Sawmill/Mine/StoneWorks = 20, TimberYard = 24 (Phase-1 "easy"
  rebalance; reverting these to 10/12 restores the harder game). A balanced 4-8
  building economy therefore yields positive net production, which is what the
  `economy` reward and `PROD_MILESTONES` reward.
- `MainGame.tscn` sets `max_deficit_duration = 40` (was 20, earlier 50 — part of the
  Phase-1 "easy" rebalance): once resources go negative the episode is still
  unrecoverable, but the longer window gives the learned signals (and a scripted
  strategy) more room to recover while learning.
