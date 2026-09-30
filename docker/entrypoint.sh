#!/usr/bin/env bash
#
# Container entrypoint. Dispatches on the first argument so a single image can
# train, evolve, or replay:
#
#   docker run --rm <image> train  --instances 2 --max_steps 200000
#   docker run --rm <image> evolution --config torch_files/evolution.yaml
#   docker run --rm <image> play --checkpoint logs/<ts>/checkpoints/final.pt
#   docker run --rm -it <image> bash
#
# Anything else is executed verbatim, which keeps `docker run <image> python ...`
# working as an escape hatch.
set -euo pipefail

# When the repo is bind-mounted for development, the image's baked .godot cache
# is shadowed. Rebuild it on first use (no-op once present) unless disabled.
if [ "${SKIP_GODOT_IMPORT:-0}" != "1" ] && [ ! -d /app/.godot ]; then
    echo "[entrypoint] /app/.godot missing - importing project (first run only)..." >&2
    godot --headless --path /app --import >&2 || true
fi

case "${1:-train}" in
    train)
        shift
        exec python -m torch_files.train "$@"
        ;;
    evolution|evo)
        shift
        exec python -m torch_files.evolution "$@"
        ;;
    orchestrator)
        shift
        exec python -m rl_tools.rl.Evolution "$@"
        ;;
    play)
        shift
        exec python -m torch_files.play "$@"
        ;;
    shell|bash)
        shift
        exec bash "$@"
        ;;
    *)
        exec "$@"
        ;;
esac
