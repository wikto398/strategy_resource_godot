# syntax=docker/dockerfile:1.7
#
# Game image: thin layer on top of the Godot engine image.
#
#   rl_tools/docker/build.sh                       # build rl-base -> rl-godot
#   docker build -f docker/Dockerfile \
#       --build-arg BASE_IMAGE=rl-godot:4.7.2 -t strategy-resource:dev .
#
# The framework layers live in the rl_tools submodule (rl_tools/docker/).
# The same game image serves both workflows:
#   * cloud / evolution  -> code baked in; the tag pins the commit.
#   * local development  -> compose bind-mounts the repo over /app, shadowing the
#                           baked copy (the /opt/venv env is outside /app and is
#                           therefore NOT shadowed).

ARG BASE_IMAGE=rl-godot:4.7.2
FROM ${BASE_IMAGE}

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

# Game code + both submodules. `.venv`, `.godot`, `logs`, `wandb` and VCS data are
# stripped by .dockerignore.
COPY . /app

# Bake the Godot import cache so headless runs start fast and deterministically
# (and so a bind-mount-free production run needs no editor pass).
RUN godot --headless --path /app --import \
    || godot --headless --path /app --editor --quit

RUN chmod +x /app/docker/entrypoint.sh

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["train"]
