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
PYTHONPATH=. rl_tools/.venv/bin/python -m rl_tools.main --instances 2 -k

# Train PPO
PYTHONPATH=. rl_tools/.venv/bin/python torch_files/train.py --instances 2 -k

# Optional: --render keeps Godot windowed; --log_level TRACE|DEBUG|INFO|...
# Python lint/format (rl_tools only; pre-commit = ruff check --fix + ruff format)
cd rl_tools && uv run ruff check --fix . && uv run ruff format .
```

No GDScript test suite in-repo. No root CI.

## Game ↔ RL protocol (easy to break)

- Transport: **UDP localhost**. Defaults in `rl_tools/utils/config.py`: obs ports `5000+id`, action ports `5500+id`, `INSTANCES=2`
- Godot reads CLI via autoload `ArgsParser`: `action_receiver_port`, `observation_receiver_port`, `python_host`, `godot_host`, `log_level`, `log_to_file`
- Handshake: env → `ENV_READY` → trainer `TRAINER_READY` → env `TRAINER_READY_ACK` → trainer `START_TRAINING`
- Observations: MessagePack dict `{observation, action_mask, reward, done}` (`ObservationCollector` + `Messagepack.encode`)
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

- Autoloads (see `project.godot`): ArgsParser, DebugLogger, Enums, Shaders, Icons, Turn, ResourceDatabase, GameData, Global
- RL loop lives under MainGame’s `EnvironmentConnector` (UDPReceiver / UDPSender / ObservationCollector / ActionExecutor) — not a separate autoload scene for training
- Shared contracts in `godot_tools`: `ActionExecutorInterface`, `ObservationCollectorInterface`, `SenderInterface`/`ReceiverInterface`
- Turn flow / win-loss: `Turn`, `Global.game_won` / `game_lost`, reward hooks via `Global.add_to_reward`
- NN: `torch_files/GameNetwork/GameNetwork.py` (attention + multi-head); agent is `PPOAgent` with TensorDicts — network owns obs processing
- Filename typo to remember: `rl_tools/rl/RLInitializer/RLIntializer.py` (imported as `RLInitializer`)

## Conventions

- Editor naming: PascalCase scripts/scenes (`project.godot` naming/*_casing=1)
- Prefer existing module folders over new top-level packages
- Match neighboring file indentation (tabs common in `modules/`; some `godot_tools` files use spaces)
- Prefer extending `godot_tools` interfaces over duplicating UDP/connector logic in the game repo
- When changing obs/action/mask shapes, update **both** Godot collectors/executors and `torch_files` + any hardcoded sizes in `train.py`
