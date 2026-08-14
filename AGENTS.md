# AGENTS.md

Godot 4.7 hex strategy game + Python RL training over UDP. Early WIP.

## Layout

| Path | Role |
|------|------|
| `modules/` | Game systems (MainGame, build/turn/builders, ActionExecutor, ObservationCollector) |
| `globals/`, `autoload/` | Autoloads + shared state (`Enums`, `GameData`, `Global`, `Turn`, `ResourceDatabase`) |
| `resources/buildings/`, `resources/structures/` | `.tres` defs loaded by `ResourceDatabase` |
| `godot_tools/` | **Git submodule** — shared Godot utils (UDP, EnvironmentConnector, grids, pathing) |
| `rl_tools/` | **Git submodule** — Python RL stack (`game_engine/`, `rl/`, `main.py`) |
| `torch_files/` | Project network + `train.py` (not a package install) |
| `ui/`, `assets/`, `shaders/` | Presentation only |

- Main scene: `modules/MainGame/MainGame.tscn`
- `rl_tools/` and `torch_files/` have `.gdignore` — Godot must not import them
- Python imports are `rl_tools.*` and `torch_files.*` → run from **repo root** with repo root on `PYTHONPATH`

## Setup

```bash
git submodule update --init --recursive
# Godot binary on PATH as `godot` (project targets 4.7)
cd rl_tools && uv sync   # Python >=3.12; torch is pinned to ROCm 7.1 index in pyproject.toml
```

- `.env` is gitignored (empty placeholder at root); `DotEnvReader` can load `res://.env`
- Do not commit `.godot/`, `logs/`, `.venv/`, `venv/`

## Commands

```bash
# Play / debug game (editor also passes --log_level=TRACE)
godot --path .

# Headless env only (ports/flags usually injected by trainer)
godot --path . --headless --action_receiver_port=5500 --observation_receiver_port=5000

# Smoke multi-instance connector (cwd = repo root so project_path default "." works)
cd /path/to/strategy_resource_godot
PYTHONPATH=. rl_tools/.venv/bin/python -m rl_tools.main --instances 2 -k --observation_class torch_files.StrategyUDPObservation.StrategyUDPObservation

# Train PPO
PYTHONPATH=. rl_tools/.venv/bin/python torch_files/train.py --instances 2 -k

# Optional: --render keeps Godot windowed; --log_level TRACE|DEBUG|INFO|...
# --torch_compile wraps the network in torch.compile (CUDA-only, off by default;
# verified bit-identical by tools/check_compile_equivalence.py, but speedup is
# modest under GPU contention; reduce-overhead mode is measurably worse here)
# Python lint/format (rl_tools only; pre-commit = ruff check --fix + ruff format)
cd rl_tools && uv run ruff check --fix . && uv run ruff format .
```

No GDScript test suite in-repo. No root CI.

## Game ↔ RL protocol (easy to break)

- Transport: **UDP localhost**. Defaults in `rl_tools/utils/config.py`: obs ports `5000+id`, action ports `5500+id`, `INSTANCES=2`
- Godot reads CLI via autoload `ArgsParser`: `action_receiver_port`, `observation_receiver_port`, `python_host`, `godot_host`, `log_level`, `log_to_file`
- Only engine-consumed args are forwarded to Godot: ports (set explicitly) plus the allowlist `GODOT_ARG_ALLOWLIST` in `RLIntializer.py` (`log_level`, `log_to_file`, `seed`, `render`). All other CLI args stay Trainer-only; pass extra engine flags with repeatable `--engine_args key=value`
- Handshake: env → `ENV_READY` → trainer `TRAINER_READY` → env `TRAINER_READY_ACK` → trainer `START_TRAINING`
- Observations: MessagePack dict `{observation, action_mask, reward, done, info}` (`ObservationCollector` + `Messagepack.encode`); `info` carries `{won, lost}` and, on the `done` step, an episode summary (`turns`, `population`, `working_population`, `total_resources`, `production`, `buildings_started`, `buildings_completed`, `reward_breakdown`) consumed by eval/play metrics
  - Wire format is a **flat binary packet** (magic `0x53 0x01`, then `fields f32(192·7) | global f32(35) | builders f32(5·6) | buildable_cells u8(10·192) | available_buildings u8(10) | moveable_cells u8(5·192) | available_builders u8(5) | real_builders u8(5) | available_skip u8(1) | reward f32 | done u8 | info_len u32 | msgpack(info)`), native little-endian. Keep the layout in sync across `modules/ObservationCollector/ObservationCollector.gd`, `torch_files/StrategyUDPObservation.py`, and the `torch_files/Factory/NetworkFactory.py` shapes. The Python decoder falls back to MessagePack if the magic is absent. `global` = 4 production + 4 stock + 7 game + 10 completed per-building counts + 10 in-progress counts (per-building counters registered in `ProductionHandler.buildings_started`/`buildings_completed`, in `ResourceDatabase.buildings` order). The generic `rl_tools` `UDPObservation` is a plain MessagePack observer; the game wires its flat protocol via the `StrategyUDPObservation` subclass, injected through `Trainer(..., observation_class=...)` (`torch_files/train.py`) or `--observation_class` on the `rl_tools.main` smoke connector.
- Actions: raw byte list via `bytearray(action)` — **not** msgpack. Layout handled by `ActionExecutor`:
  - `0` next turn
  - `1, builder_id, _, cell_flat` move
  - `2, _, building_type, cell_flat` build
- Reset: trainer sends `RESET`, env replies `RESET_ACK`, then `Global.reset_environment()` reloads scene
- `-k` / `--kill_existing` runs `pkill -f 'godot.*--headless'` — avoid with unrelated headless Godot processes
- Headless path defaults `project_path="."` → **cwd must be repo root** when launching trainers
- Grid is **16×12** hex (`TerrainFieldGrid`); cell indices are flat (`flat_to_2d_index`)
- `GameData.MAX_BUILDERS = 5`; masks pad builder dims to that
- Building int IDs come from recursive `.tres` load order under `resources/buildings/` — changing file order changes agent indices; keep in sync with `GameNetwork(..., n_buildings=...)`

## Architecture notes

- Autoloads (see `project.godot`): ArgsParser, RewardConfig, DebugLogger, Enums, Shaders, Icons, Turn, ResourceDatabase, GameData, Global
- Reward coefficients live as plain vars on the `RewardConfig` autoload (`globals/RewardConfig.gd`); override at launch via `--engine_args` or `config.yaml` `engine_args:` (see `rewards.md`)
- RL loop lives under MainGame’s `EnvironmentConnector` (UDPReceiver / UDPSender / ObservationCollector / ActionExecutor) — not a separate autoload scene for training
- Shared contracts in `godot_tools`: `ActionExecutorInterface`, `ObservationCollectorInterface`, `SenderInterface`/`ReceiverInterface`
- Turn flow / win-loss: `Turn`, `Global.game_won` / `game_lost`, reward hooks via `Global.add_to_reward`
- NN: `torch_files/GameNetwork/GameNetwork.py` (attention + multi-head); agent is `PPOAgent` with TensorDicts — network owns obs processing
- Filename typo to remember: `rl_tools/rl/RLInitializer/RLIntializer.py` (imported as `RLInitializer`)
- Training orchestration: generic `rl_tools/rl/Trainer` (train + sweep); game-specific construction injected via singleton factories `torch_files/Factory/` (`StrategyNetworkFactory`, `StrategyCallbacksFactory`, `StrategyNormalizersFactory`, `instance()` pattern) implementing the ABCs in `rl_tools/rl/Factory/`.
- Training metrics hooks: `rl_tools/rl/Callback` (`Callback` ABC, `NoOpCallback`, `CallbackList`) passed as `PPOAgent(..., callback=...)`. Game-specific metrics live in `torch_files/callbacks/` (e.g. `StrategyMetricsCallback` records action-type/building/builder/cell + rollout stats to the blackboard). Subclass `Callback` and implement all abstract hooks for other games; compose with `CallbackList`.

## Logging

Metrics flow through a shared **Blackboard** (`rl_tools/rl/Blackboard/Blackboard.py`):
producers write records via `agent.blackboard.record(key, value, step)` /
`record_histogram(...)` / `set(...)`, and **sink callbacks** drain them. Sinks all
extend `SinkCallback` (`rl_tools/rl/Callback/SinkCallback/`) — to add a new output,
subclass it and implement `_write_scalar` / `_write_histogram`.

- Producers (never touch TB/W&B directly): `EvalCallback`, `StrategyMetricsCallback`,
  `TimingCallback`, PPOAgent loss/norm_scale logging. `EvalCallback` is generic
  (returns/win-rate via a configurable `won_key`; inject a subclass via
  `Trainer(..., eval_callback_class=...)`) and publishes a structured `eval/latest`
  dict on the blackboard (win_rate, returns, length…). The game's terminal-summary
  metrics (`eval/breakdown/*`, `eval/buildings_*`, `eval/mean_win_turns` /
  `mean_loss_turns`, `eval/mean_end_*`) are emitted by
  `torch_files/StrategyEvalCallback`, which overrides `_log_episode_summary`.
- Sinks (appended **after** `EvalCallback` so eval data is flushed in the same update):
  - `ConsoleCallback` — `logger.info("Step N: key = value")` at INFO
  - `TensorboardCallback` — `SummaryWriter` (when enabled)
  - `WandbCallback` — `wandb.run` (when enabled), incl. `eval/latest` as a `wandb.Table`
  - `CsvCallback` — long-format `step,key,value` dump of every blackboard scalar to
    `<log_path>/metrics.csv` (off by default; enable with `--csv_metrics`). Load with
    `pandas.read_csv` then `df[df.key == "eval/win_rate"]` or pivot on `step`. Histograms
    are skipped.
- **Auto-clear**: once every registered sink cursor has passed an event id, the event is
  purged (min-cursor watermark, batched every `Blackboard.CLEAR_BATCH_SIZE = 4096`
  events) so the log stays bounded. A lagging sink blocks clearing until it catches up.
- TensorBoard is **on by default**: `SummaryWriter` writes `logs/<ts>/tensorboard/`;
  `--tensorboard_port N` additionally serves a live server. Pass `--no_tensorboard` to
  disable the writer entirely (also skips the server; `--tensorboard_port` is then
  ignored with a warning).
- W&B is **off by default**; enable with `--wandb_project <name>`:
  - `--wandb_entity`, `--wandb_name` (default `logs/<ts>` basename), `--wandb_tags a,b,c`
  - Runs launched with `--expert_eps > 0` are **auto-tagged `expert-assisted`** (appended
    by `Trainer._wandb_tags()`, deduped against `--wandb_tags`) — no need to pass it
    manually
  - `--wandb_group <name>` groups related runs together in the dashboard; a resumed run
    cannot share a W&B run id with its finished predecessor (W&B forbids resuming
    `finished` runs), so keep segments of one experiment together with a shared
    `--wandb_name <exp> --wandb_group <exp>` on every continuation
  - `--wandb_mode offline|online|disabled` (default `offline` — no network)
  - Run files (config/scalars/histograms) land in `logs/<ts>/wandb/offline-run-*`
    alongside other logs (already gitignored via `logs/`). Sync later:
    ```bash
    wandb sync logs/<ts>/wandb/offline-run-* -p <project>
    ```
    (`wandb sync --include-offline` only auto-searches the repo-root `./wandb/`, so
    point it at the run path for runs under `logs/`.)
  - W&B init/config is built in `rl_tools/rl/Trainer` via `rl_tools/rl/WandbWrapper`
    (full PPO/optimizer/game config); `wandb.finish()` runs in the Trainer's `finally`.
  - Full per-metric history is stored natively by W&B (each scalar is logged with its
    step), so complete training curves are available in the dashboard; grouped
    multi-line views can be built there.

### Sweeps

- Hyperparameter sweeps run through the generic `rl_tools/rl/Trainer` +
  `WandbWrapper.sweep()` (which wraps `wandb.sweep` + `wandb.agent`).
  Game-specific construction is injected via **singleton factories**
  (`torch_files/Factory/`, `instance()` classmethod pattern) implementing the ABCs in
  `rl_tools/rl/Factory/` — add a new game by implementing `NetworkFactory` /
  `CallbacksFactory` / `NormalizersFactory`; no Trainer changes.
- Search space is a **YAML** file (example: `torch_files/sweep.yaml`); sweepable knobs
  are forwarded straight to `PPOAgent(**params)` (agent defaults fill the rest), so
  the sweep `parameters` keys must match PPOAgent constructor kwargs. Only `lr` is
  special-cased by the Trainer (it builds the optimizer).
- Run:
  ```bash
  python -m torch_files.train --instances=8 --eval_episodes 20 --eval_instances 4 \
    --eval_every_timesteps 2048 --seed 42 --render_eval \
    --wandb_project strategy-resource --wandb_mode online \
    --sweep_config torch_files/sweep.yaml --sweep_count 10 --max_steps 1_000_000
  ```
  `--seed N` seeds Python/NumPy/PyTorch RNG (`_seed_rng` in `rl_tools/rl/Trainer`) **and** the Godot
  map stream. Sweep trials each re-seed with the same base seed, so per-trial differences come
  only from the sampled hyperparameters. `torch_files/play.py` seeds the same way.
  `--max_steps N` stops each run at ~N global steps (overrides `--iterations`;
  derived as `ceil(max_steps / (rollout_size * instances))`). Without it, `--iterations`
  governs.
- `--sweep_config` requires **online mode** (or a self-hosted W&B server); the Trainer
  raises on `offline`/`disabled`. Trials run sequentially in one agent process (no
  Godot port conflicts). Sampled hyperparameters are recorded in `run.config` via
  `config.update()`; the search metric is `eval/win_rate`.

### YAML config (non-sweep)

- `--config torch_files/config.yaml` loads hyperparameters and CLI flags from a YAML
  file so a good sweep trial can be replayed standalone (example committed).
  `hyperparams` keys map straight to `PPOAgent`/Adam (the sweepable set + extras:
  `lr, gamma, lam, epochs, batch_size, rollout_size, entropy_coef_*, entropy_target,
  entropy_adapt_lr, adaptive_entropy, clip_epsilon, value_loss_coef`). `cli` keys map
  to any argparse dest. `engine_args` keys are forwarded verbatim to every Godot
  instance (train + eval), same path as repeatable CLI `--engine_args` (CLI wins on
  key conflicts) — used for game-side knobs like the `RewardConfig` reward
  coefficients (`globals/RewardConfig.gd`). (`torch_files/sweep_config.yaml` holds
  the base sweep params; the swept search space lives in `torch_files/sweep.yaml`.)
- **CLI flags override the file**; the file only fills values not set on the command
  line. Unknown keys are ignored with a warning. Applies to non-sweep runs only
  (`--sweep_config` ignores `--config`).
- **YAML gotcha:** write `lr` as `0.0003` (PyYAML parses `3e-4` as a string, not a
  float).

### Early stopping

Both callbacks live in `rl_tools/rl/Callback/StopTrainingCallback/`, read the metric
from the blackboard's `eval/latest` dict (so they must be wired **after** `EvalCallback`),
and stop gracefully via `request_stop()` (clean checkpoint + W&B finish; a sweep then
moves to the next trial). They are appended to the flat `CallbackList` in the Trainer.

- **`MetricStopCallback`** (persistent pruning): `--stop_metric <name>`
  (e.g. `win_rate`), `--stop_threshold 0.05`, `--stop_patience 3`. Stops when the metric
  stays bad (below/above threshold per `--gate_goal`/default below) for `patience`
  consecutive evals; the counter resets on recovery.
- **`GateStopCallback`** (one-shot go/no-go): fires once when `global_step >= step`,
  stops if the metric is bad, otherwise lets the run continue — then **detaches itself**
  (`Callback.detach()` → `CallbackList.remove`). Multiple gates are supported:
  - single gate via the legacy flags `--gate_step <N> --gate_metric win_rate
    --gate_threshold 0.05 --gate_goal below|above`
  - repeatable `--gate "step,metric,threshold[,goal]"` flags (one per gate)
  - a YAML list via `--gates_config torch_files/gates.yaml` (`gates:` entries with
    `step/metric/threshold/goal`, goal defaults to `below`)
  All sources combine; each gate is independent and any failure stops the run.
  The two callbacks can be combined (`--stop_metric` + gates).

### Expert-in-the-loop coach

- **Purpose**: bootstrap hard exploration — the agent converges to inaction/spam
  because the balanced win line is never sampled. A scripted expert overrides a
  fraction of training actions on-policy so good trajectories appear in the data
  (value function learns their worth + an imitation push on the actions).
- **Flags**: `--expert_eps 0.4 --expert_eps_decay_steps 200000` (ε linearly decays
  to 0; at 0 the expert is inert). The **number of instances and steps per
  iteration is constant forever** — the expert is a per-step action override
  inside the existing envs, never extra/removed envs. Eval envs are always pure
  agent, so `eval/win_rate` measures the real policy.
- **Mechanics** (`rl_tools/rl/RLAgent/PolicyGradientAgent.py::_apply_expert_actions`):
  after `get_action`, with prob `current_expert_eps()` per env the sampled action
  is replaced with the expert's and its **log-prob recomputed under the current
  policy** so stored `actions`/`log_probs` stay consistent for the PPO ratio
  (batched over the selected envs; skipped when the expert agrees with the agent).
  This is the on-policy "coach" setup: the ε-fraction is technically off-policy
  w.r.t. the agent's induced state distribution (standard guided-RL tradeoff),
  acceptable because ε→0. Eval envs are always pure agent.
- **NaN/stability guards**: expert actions are mask-valid by construction (moves
  only to `moveable_cells[builder]`, builds only to `buildable_cells[building]`,
  skip gated on `available_skip`, else a fallback legal action), so stored
  log-probs are finite. `PPOAgent.update` additionally clamps old/new log-probs
  (`LOG_PROB_FLOOR`) and the log-ratio (`LOG_RATIO_CLAMP`), because expert actions
  can be very low-probability under the agent's fresh policy and `exp` would
  otherwise explode.
- **Interface**: generic `ExpertInterface` ABC (`rl_tools/rl/Factory/`) + game
  expert `torch_files/Expert/StrategyExpert.py` (a Python port of
  `tools/scripted_play.gd`'s "balanced" policy operating on raw obs + masks),
  injected via `StrategyExpertFactory` (`torch_files/Factory/ExpertFactory.py`).
  Add a new game's expert by implementing `ExpertInterface`/`ExpertFactory`.
- **Obs note**: empty cells and the City Center both report building int `0` in
  `fields`, so `StrategyExpert` detects "city center not built" via the mask
  (`available_buildings[0] == 1`), not the field tensor.

## Conventions

- Editor naming: PascalCase scripts/scenes (`project.godot` naming/*_casing=1)
- Prefer existing module folders over new top-level packages
- Match neighboring file indentation (tabs common in `modules/`; some `godot_tools` files use spaces)
- Prefer extending `godot_tools` interfaces over duplicating UDP/connector logic in the game repo
- When changing obs/action/mask shapes, update **both** Godot collectors/executors and `torch_files` + any hardcoded sizes in `train.py`
