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
| `skip` | `_skip_reward()` | `-0.05` |
| `time` | `_time_penalty()` | `-0.01` |
| `deficit` | `_deficit_penalty()` | `-0.025 * min(5, deficit_duration)` per resource with `town_resources[r] <= 0` |
| `production` | `_production_penalty()` | `-0.02 * min(10, \|net_production\|)` per resource with `current_production[r] <= 0` |
| `economy` | `_economy_reward()` | `+0.05 * Σ net_production` (negatives subtract — single-type spam no longer earns positive-only rewards) |
| `balance` | `_balance_reward()` | `+0.125` per resource with positive net production (max `+0.5` when all 4 positive) |
| `stock_warning` | `_stock_warning()` | `-0.05 * min(3, max(0, 1 - stock_r/100))` per resource |
| `milestones` | `_milestones()` | pop [4,5,6,8] -> +0.5 each; net prod [5,10,20,30] -> +1.0 each; `+0.02` per unit above rolling stock peak |
| `stockpile` | `_stockpile_reward()` | per-resource min stock crossing [800,1200,1500] -> +1.0 each (aligns with Workshop win cost) |
| `productive` | `_productive_turn()` | `+0.15` if any builder is `building` or net production > 0 — **gated off** when at the population ceiling with no positive net production |
| `construction` | `_construction_reward()` | `+0.05` per building currently in progress (credits the build window while upkeep drains) |
| `win_progress` | `_win_progress()` | potential-based: `Φ = 0.002 * Σ completed build cost`, reward `γ*Φ(t) - Φ(t-1)` |

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
| Over-commit (starting any building while `working_population + in_progress_buildings > population`) | `-1.0` (`over_commit`) |
| + tagged events | building start/finish/first-of-type bonuses emitted during the action |

### Events

| Tag | Source | Reward |
|---|---|---|
| `build_start` | `ProductionHandler.start_production` | `+min(2.0, 0.10 * total_build_cost / 100)` |
| `build_finish` | production buildings | `+0.5 * production_rate / (1 + count_of_type_completed)` — diminishing: 1st = 5.0, 2nd = 2.5, 3rd = 1.67… (anti single-type spam) |
| `resource_gap` | production buildings | `+0.05 * clamp(GAP_TARGET - projected_production_of_produced_resource, 0, 10)` — `projected` = completed production + production of **all in-progress** buildings of that type. Up to `+0.5` when under-produced (net < 10), `0` once saturated. Counts in-progress so parallel spam fills the gap immediately (5 Mines in flight → projected ≥ 25 → 0 for every completion); a lone genuine build still earns the bonus |
| `first_build` | first completion of each building type | `+3.0` |
| `housing` | Housing (only while fully employed) | `+0.3 * population_increase` |
| `events` (default) | Special (`+0.5`) | varies |

## Terminal reward

`_result_score()` (applied once, on the `done` step):

```
score = (+25 if won else -10)
      + production_bonus   (Σ current_production * 0.1)
      + progress_bonus     ((population + working_population) * 0.1)
```

## Observability

Per-step components are accumulated into `episode_components` and logged at
`INFO` when the episode ends:

```
Episode ended (WON|LOST). Reward breakdown: {"time": ..., "stock_warning": ..., ...}
```

Component keys: `time`, `deficit`, `production`, `economy`, `stock_warning`,
`milestones`, `stockpile`, `productive`, `construction`, `win_progress`,
`build_start`, `build_finish`, `first_build`, `events`, `move`, `skip`, `build`,
`over_commit`, `balance`, `housing`, `resource_gap`, `terminal`.

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

## Notes

- `last_action` is set from the parsed action in `ActionExecutor`; the reward is
  computed on the next observation, so it reflects the effects of that action.
- Penalties/shaping fire once per turn (on the next-turn action), not per action.
- Milestone/peak state lives on the collector and resets with each episode (scene
  reload). Thresholds are chosen so they are not passed at game start (start pop is 3,
  start net production is 0, start stock is 500 per resource; stockpile milestones
  start at 800 so the agent must actually save, and prod milestones require positive
  net production).
- The over-commit penalty (`over_commit`) fires on the build action itself (not the
  next-turn action) when **any** building is started while
  `working_population + in_progress_buildings > population`. This stops the
  "start 18 buildings, complete 3" death spiral: with no Housing, population stays at 3,
  so at most 3 buildings can ever be under construction, and extras stall forever
  while draining upkeep. Applies to Housing too (its 4-resource upkeep drains with no
  production).
- `production`/`deficit` penalties are moderate (`-0.02 * min(10,|net|)`,
  `-0.025 * min(5,duration)`) so that building — which applies upkeep at start but only
  produces at completion — is not overwhelmed by the temporary bleed. The `construction`
  component additionally credits every in-progress building each turn. The economy reward
  nets all four resources (negatives subtract) and `balance` pays `+0.125` per positive
  resource, so a mixed/balanced economy earns more than single-type spam.
- Production rates (defined in `resources/buildings/production/*/*.tres`, upkeep
  unchanged): Farm/Sawmill/Mine/StoneWorks = 10, TimberYard = 12. A balanced 4-8
  building economy therefore yields positive net production, which is what the
  `economy` reward and `PROD_MILESTONES` reward.
- `MainGame.tscn` sets `max_deficit_duration = 20` (was 50): once resources go
  negative the episode is unrecoverable, so a shorter deficit window cuts the doomed
  tail of pure penalty from ~50 turns to ~20, giving the learned signals more weight.
