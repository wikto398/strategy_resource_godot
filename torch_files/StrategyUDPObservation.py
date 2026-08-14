from __future__ import annotations

import msgpack
import numpy as np

from rl_tools.game_engine.ObservationInterface.UDPObservation import UDPObservation

# Flat binary observation protocol. Layout must stay in sync with
# modules/ObservationCollector/ObservationCollector.gd and
# torch_files/Factory/NetworkFactory.py (AGENTS.md). Native little-endian.
MAGIC = 0x53
VERSION = 0x01
N_CELLS = 192  # 16x12 grid
N_CELL_FEATURES = 7
N_GLOBAL_FEATURES = (
    35  # 4 production + 4 stock + 7 game + 10 completed + 10 in-progress
)
N_BUILDERS = 5  # GameData.MAX_BUILDERS
N_BUILDER_FEATURES = 6
N_BUILDINGS = 10
HEADER = 2  # magic + version


class StrategyUDPObservation(UDPObservation):
    """UDP observer for this game's flat binary observation packet.

    Subclasses the generic :class:`UDPObservation` and adds the flat protocol
    decode (magic-prefixed), falling back to MessagePack when the magic is
    absent.
    """

    def parse_observation(self, raw_observation: bytes | None) -> dict | None:
        if raw_observation is None:
            return None
        if (
            len(raw_observation) >= HEADER
            and raw_observation[0] == MAGIC
            and raw_observation[1] == VERSION
        ):
            return self._parse_flat(raw_observation)
        return super().parse_observation(raw_observation)

    def _parse_flat(self, data: bytes) -> dict | None:
        # Writable buffer so torch.from_numpy in split_observation gets writable
        # arrays (avoids the non-writable-tensor warning).
        p = bytearray(data[HEADER:])
        off = 0

        def take_f32(n: int) -> np.ndarray:
            nonlocal off
            arr = np.frombuffer(p[off : off + n * 4], np.float32)
            off += n * 4
            return arr

        def take_u8(n: int) -> np.ndarray:
            nonlocal off
            arr = np.frombuffer(p[off : off + n], np.uint8)
            off += n
            return arr

        try:
            fields = take_f32(N_CELLS * N_CELL_FEATURES).reshape(
                N_CELLS, N_CELL_FEATURES
            )
            global_features = take_f32(N_GLOBAL_FEATURES)
            builders = take_f32(N_BUILDERS * N_BUILDER_FEATURES).reshape(
                N_BUILDERS, N_BUILDER_FEATURES
            )
            buildable_cells = take_u8(N_BUILDINGS * N_CELLS).reshape(
                N_BUILDINGS, N_CELLS
            )
            available_buildings = take_u8(N_BUILDINGS)
            moveable_cells = take_u8(N_BUILDERS * N_CELLS).reshape(N_BUILDERS, N_CELLS)
            available_builders = take_u8(N_BUILDERS)
            real_builders = take_u8(N_BUILDERS)
            available_skip = take_u8(1)[0]
            reward = float(take_f32(1)[0])
            done = bool(take_u8(1)[0])
            info_len = int(np.frombuffer(p[off : off + 4], np.uint32)[0])
            info = msgpack.unpackb(p[off + 4 : off + 4 + info_len], raw=False)
        except (ValueError, IndexError) as e:
            self._logger.error(f"Could not parse flat observation: {e}")
            return None

        return {
            "observation": {
                "fields": fields,
                "global": global_features,
                "builders": builders,
            },
            "action_mask": {
                "buildable_cells": buildable_cells,
                "available_buildings": available_buildings,
                "moveable_cells": moveable_cells,
                "available_builders": available_builders,
                "real_builders": real_builders,
                "available_skip": available_skip,
            },
            "reward": reward,
            "done": done,
            "info": info,
        }
