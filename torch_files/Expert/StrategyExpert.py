from __future__ import annotations

import numpy as np
import torch
from tensordict import TensorDict

from rl_tools.rl.Factory import ExpertInterface

# Grid layout: 16 columns x 12 rows, flat index = x + COLUMNS * y (must stay in
# sync with modules/ObservationCollector and torch_files/Factory/NetworkFactory.py).
COLUMNS = 16

# Building int IDs in ResourceDatabase / BUILDING_NAMES order.
CITY_CENTER, HOUSING, FARM, STONE_WORKS, TIMBER_YARD, MINE, SAWMILL = range(7)
WORKSHOP = 9

# Enums.TownResource order in the global observation (production[0:4], stock[4:8]).
WOOD, STONE, FOOD, GOLD = 0, 1, 2, 3

# Resource -> producer building int (Farm for FOOD, etc.).
PRODUCERS = {WOOD: SAWMILL, STONE: MINE, FOOD: FARM}
GOLD_PRODUCERS = [STONE_WORKS, TIMBER_YARD]

# Workshop build cost (1500 of each resource) — used for affordability.
WORKSHOP_COST = [1500, 1500, 1500, 1500]
MAX_POPULATION_TARGET = 6


class StrategyExpert(ExpertInterface):
    """Python port of ``tools/scripted_play.gd``'s "balanced" policy.

    Operates purely on the raw observation + action masks (no game internals):
    rebuilds the terrain/building map from ``fields``, reads economy/population
    from ``global`` and builder positions from ``builders``, and picks buildable
    cells from the ``buildable_cells`` mask. Returns the network's integer action
    vector ``[action, builder, building, cell]`` (move/build/skip).
    """

    def action(
        self,
        obs: TensorDict,
        action_mask: TensorDict | None = None,
    ) -> TensorDict:
        batch_obs = obs["observation"]
        batch_mask = action_mask if action_mask is not None else obs.get("action_mask")
        B = batch_obs["fields"].shape[0]
        actions = torch.zeros((B, 4), dtype=torch.long)

        fields = batch_obs["fields"].numpy()
        global_features = batch_obs["global"].numpy()
        builders = batch_obs["builders"].numpy()

        mask: dict[str, np.ndarray] | None = None
        if batch_mask is not None:
            # SIM118: TensorDict iteration is not dict-like; must use .keys().
            mask = {key: batch_mask[key].numpy() for key in batch_mask.keys()}  # noqa: SIM118

        for i in range(B):
            mask_i = {key: value[i] for key, value in mask.items()} if mask else None
            actions[i] = torch.tensor(
                self._act(fields[i], global_features[i], builders[i], mask_i),
                dtype=torch.long,
            )
        return TensorDict({"action": actions}, batch_size=[B])

    def _act(
        self,
        fields: np.ndarray,
        global_features: np.ndarray,
        builders: np.ndarray,
        mask: dict[str, np.ndarray] | None,
    ) -> list[int]:
        if mask is None:
            return [0, 0, 0, 0]

        buildable = mask["buildable_cells"]  # (10, 192)
        available = mask["available_buildings"]  # (10,)
        avail_builders = mask["available_builders"]  # (5,)
        moveable = mask["moveable_cells"]  # (5, 192)
        can_skip = bool(mask["available_skip"])

        stock = global_features[4:8]
        pop = int(global_features[10])
        working = int(global_features[11])
        current_builders = int(global_features[12])

        in_progress = fields[:, 5]  # in-progress building int per cell
        building_here = fields[:, 2]  # completed building int per cell

        def in_progress_count() -> int:
            return int((in_progress != 0).sum())

        def has_buildable_cell(building_int: int) -> bool:
            return bool(buildable[building_int].any())

        def can_start(building_int: int, allow_full: bool) -> bool:
            if not available[building_int] or not has_buildable_cell(building_int):
                return False
            used = working + in_progress_count()
            if allow_full:
                if used > pop:
                    return False
            else:
                if used >= pop:
                    return False
            return not in_progress_count() >= current_builders

        def skip_or_fallback() -> list[int]:
            if can_skip:
                return [0, 0, 0, 0]
            return self._fallback_action(
                buildable, available, moveable, builders, avail_builders, in_progress
            )

        # City Center must be built first: the mask reports it as the only
        # available building (available_buildings[0] == 1) until it is placed.
        if available[CITY_CENTER] == 1:
            target = CITY_CENTER
        else:
            target = self._choose_building(
                stock,
                pop,
                working,
                current_builders,
                building_here,
                in_progress,
                buildable,
                available,
            )
            if target is None:
                return skip_or_fallback()

        pair = self._find_cell_and_builder(
            target, buildable, moveable, builders, avail_builders, in_progress
        )
        if pair is None:
            if not bool(avail_builders.any()) and not bool(moveable.any()):
                # Fully stuck (pre-City-Center bootstrap: no idle builder, no
                # moveable cells, skip not allowed) — the only legal action is
                # to build the target (City Center) directly; builders and the
                # skip action become available once it is placed.
                cell = self._nearest_buildable_cell(target, buildable, builders)
                if cell is not None:
                    return [2, 0, target, cell]
            return skip_or_fallback()
        cell, builder_id = pair
        if self._has_mover_to(cell, builders):
            return skip_or_fallback()

        bx, by = int(builders[builder_id][0]), int(builders[builder_id][1])
        if bx >= 0 and bx + COLUMNS * by == cell:
            return [2, 0, target, cell]
        return [1, builder_id, 0, cell]

    def _choose_building(
        self,
        stock: np.ndarray,
        pop: int,
        working: int,
        current_builders: int,
        building_here: np.ndarray,
        in_progress: np.ndarray,
        buildable: np.ndarray,
        available: np.ndarray,
    ) -> int | None:
        def can_start(building_int: int, allow_full: bool) -> bool:
            if not available[building_int] or not bool(buildable[building_int].any()):
                return False
            used = working + int((in_progress != 0).sum())
            if allow_full:
                if used > pop:
                    return False
            else:
                if used >= pop:
                    return False
            return not int((in_progress != 0).sum()) >= current_builders

        def has_producer(resource: int) -> bool:
            def count(building_int: int) -> int:
                return int((building_here == building_int).sum()) + int(
                    (in_progress == building_int).sum()
                )

            if resource == GOLD:
                if count(MINE) == 0:
                    return False
                return count(STONE_WORKS) > 0 or count(TIMBER_YARD) > 0
            return count(PRODUCERS[resource]) > 0

        # Workshop once affordable.
        if can_start(WORKSHOP, allow_full=True) and all(
            stock[r] >= WORKSHOP_COST[r] for r in range(4)
        ):
            return WORKSHOP

        # Housing to grow population (keep a spare worker while building).
        in_progress_housing = int((in_progress == HOUSING).sum())
        if (
            pop + in_progress_housing < MAX_POPULATION_TARGET
            and working >= pop - 2
            and can_start(HOUSING, allow_full=True)
        ):
            return HOUSING

        # One producer per missing resource; FOOD first, then lowest stock.
        missing = [r for r in range(4) if not has_producer(r)]
        missing.sort(key=lambda r: (0 if r == FOOD else 1, int(stock[r])))
        for resource in missing:
            candidate = self._producer_for(resource, buildable)
            if candidate is not None and can_start(candidate, allow_full=False):
                return candidate
        return None

    def _producer_for(self, resource: int, buildable: np.ndarray) -> int | None:
        if resource != GOLD:
            return PRODUCERS[resource]
        for candidate in GOLD_PRODUCERS:
            if bool(buildable[candidate].any()):
                return candidate
        return GOLD_PRODUCERS[0]

    @staticmethod
    def _nearest_buildable_cell(
        building_int: int,
        buildable: np.ndarray,
        builders: np.ndarray,
    ) -> int | None:
        """Nearest buildable cell for ``building_int`` to any builder position
        (used to place a building directly when no builder is movable yet)."""
        cells = np.nonzero(buildable[building_int])[0]
        if len(cells) == 0:
            return None
        best: int | None = None
        best_dist = float("inf")
        for flat in cells:
            cx, cy = int(flat) % COLUMNS, int(flat) // COLUMNS
            dist = float("inf")
            for b in builders:
                bx, by = int(b[0]), int(b[1])
                if bx < 0:
                    continue
                dist = min(dist, abs(bx - cx) + abs(by - cy))
            if dist < best_dist:
                best_dist = dist
                best = int(flat)
        return best

    @staticmethod
    def _find_cell_and_builder(
        building_int: int,
        buildable: np.ndarray,
        moveable: np.ndarray,
        builders: np.ndarray,
        avail_builders: np.ndarray,
        in_progress: np.ndarray,
    ) -> tuple[int, int] | None:
        """Nearest (cell, idle builder) where the cell is buildable for the
        building *and* reachable by that builder (keeps move actions mask-valid)."""
        best: tuple[int, int] | None = None
        best_dist = float("inf")
        for i, b in enumerate(builders):
            if avail_builders[i] != 1:
                continue
            bx, by = int(b[0]), int(b[1])
            if bx < 0:
                continue
            if in_progress[bx + COLUMNS * by] != 0:
                continue  # committed to a construction site
            if not bool(moveable[i].any()):
                continue  # no reachable cell -> builder would be masked out
            cells = np.nonzero(buildable[building_int] & moveable[i])[0]
            for cell in cells:
                cx, cy = int(cell) % COLUMNS, int(cell) // COLUMNS
                dist = abs(bx - cx) + abs(by - cy)
                if dist < best_dist:
                    best_dist = dist
                    best = (int(cell), i)
        return best

    @staticmethod
    def _fallback_action(
        buildable: np.ndarray,
        available: np.ndarray,
        moveable: np.ndarray,
        builders: np.ndarray,
        avail_builders: np.ndarray,
        in_progress: np.ndarray,
    ) -> list[int]:
        """Guarantee a mask-valid action when the balanced decision has no
        valid (cell, builder) pair (e.g. skip is not allowed pre-City-Center).

        Builds only when an idle builder is already on the buildable cell (a
        building started without a builder on site stalls forever), otherwise
        moves a builder toward the nearest reachable buildable cell.
        """
        n_buildings = buildable.shape[0]
        # 1) Build if an idle builder is already standing on a buildable cell.
        for i, b in enumerate(builders):
            if avail_builders[i] != 1:
                continue
            bx, by = int(b[0]), int(b[1])
            if bx < 0:
                continue
            flat = bx + COLUMNS * by
            if in_progress[flat] != 0:
                continue
            for building_int in range(n_buildings):
                if available[building_int] and buildable[building_int][flat]:
                    return [2, 0, building_int, flat]
        # 2) Move an idle builder toward the nearest reachable buildable cell.
        best: tuple[int, int] | None = None
        best_dist = float("inf")
        for i, b in enumerate(builders):
            if avail_builders[i] != 1:
                continue
            bx, by = int(b[0]), int(b[1])
            if bx < 0:
                continue
            if in_progress[bx + COLUMNS * by] != 0:
                continue
            for cell in np.nonzero(moveable[i])[0]:
                if not any(
                    available[bint] and buildable[bint][cell]
                    for bint in range(n_buildings)
                ):
                    continue
                cx, cy = int(cell) % COLUMNS, int(cell) // COLUMNS
                dist = abs(bx - cx) + abs(by - cy)
                if dist < best_dist:
                    best_dist = dist
                    best = (i, int(cell))
        if best is not None:
            return [1, best[0], 0, best[1]]
        # 3) Any move (keep the builder useful) as a last resort.
        for i in range(moveable.shape[0]):
            cells = np.nonzero(moveable[i])[0]
            if len(cells) == 0:
                continue
            return [1, i, 0, int(cells[0])]
        return [0, 0, 0, 0]

    @staticmethod
    def _has_mover_to(cell: int, builders: np.ndarray) -> bool:
        for b in builders:
            tx, ty = int(b[2]), int(b[3])
            if tx >= 0 and tx + COLUMNS * ty == cell:
                return True
        return False
