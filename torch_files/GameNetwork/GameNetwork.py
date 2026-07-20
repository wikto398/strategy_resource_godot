from tensordict import TensorDict
import torch
import torch.nn as nn
from torch.distributions import Categorical
import numpy as np

class GameNetwork(nn.Module):
    def __init__(self, n_cell_features, n_global_features, n_buildings, n_builder_features, d_model=256, n_heads=8):
        super().__init__()
        self.n_buildings = n_buildings

        self.cell_encoder = nn.Sequential(
            nn.Linear(n_cell_features, d_model),
            nn.ReLU(),
        )
        self.global_encoder = nn.Sequential(
            nn.Linear(n_global_features, d_model),
            nn.ReLU(),
        )
        self.builder_encoder = nn.Sequential(
            nn.Linear(n_builder_features, d_model),
            nn.ReLU(),
        )
        self.building_encoder = nn.Embedding(n_buildings, d_model)

        self.builder_to_builder_attention = nn.MultiheadAttention(d_model, n_heads, batch_first=True)
        self.builder_to_cell_attention = nn.MultiheadAttention(d_model, n_heads, batch_first=True)
        self.builder_to_global_attention = nn.MultiheadAttention(d_model, n_heads, batch_first=True)

        self.norm1 = nn.LayerNorm(d_model)
        self.norm2 = nn.LayerNorm(d_model)
        self.norm3 = nn.LayerNorm(d_model)

        self.action_head = nn.Linear(d_model, 3)
        self.builder_head = nn.Linear(d_model, 1)
        self.building_head = nn.Linear(d_model, n_buildings)
        self.move_cell_head = nn.Linear(d_model * 2, 1)
        self.build_cell_head = nn.Linear(d_model * 3, 1)
        self.value_head = nn.Linear(d_model, 1)

    def _get_logits(self, obs: TensorDict, action_mask: TensorDict | None) -> TensorDict:
        cell_features    = obs["fields"]    # (B, cells, cell_features)
        global_features  = obs["global"]   # (B, global_features)
        builder_features = obs["builders"] # (B, builders, builder_features)
        B = cell_features.size(0)
        n_builders = builder_features.size(1)
        n_buildings = self.n_buildings
        n_cells = cell_features.size(1)

        device = cell_features.device

        moveable_cells      = action_mask["moveable_cells"]      if action_mask is not None else torch.ones((B, n_builders, n_cells), dtype=torch.bool, device=device) # (B, builders, cells)
        buildable_cells     = action_mask["buildable_cells"]     if action_mask is not None else torch.ones((B, n_buildings, n_cells), dtype=torch.bool, device=device)  # (B, n_buildings, cells)
        available_buildings = action_mask["available_buildings"] if action_mask is not None else torch.ones((B, n_buildings), dtype=torch.bool, device=device)  # (B, n_buildings)
        available_builders = action_mask["available_builders"]    if action_mask is not None else torch.ones((B, n_builders), dtype=torch.bool, device=device)  # (B, n_builders)

        # Cell and global features encoding
        cell_encoded   = self.cell_encoder(cell_features)              # (B, cells, d_model)
        global_encoded = self.global_encoder(global_features)          # (B, d_model)

        # Building encoding
        bt = self.building_encoder(torch.arange(n_buildings, device=device))  # (n_buildings, d_model)
        bt = bt.unsqueeze(0).expand(B, -1, -1)  # (B, n_buildings, d_model)

        # Build cell logits computation
        g_exp = global_encoded[:,None,None,:].expand(
            B,
            n_buildings,
            n_cells,
            -1
        )


        bt_exp = bt.unsqueeze(2).expand(-1, -1, n_cells, -1)          # (B, n_buildings, n_cells, d_model)
        c_exp2 = cell_encoded.unsqueeze(1).expand(-1, self.n_buildings, -1, -1)
        btc = torch.cat(
            [
                bt_exp,
                c_exp2,
                g_exp
            ],
            dim=-1
        ) # (B, n_buildings, n_cells, d_model*3)
        build_cell_logits = self.build_cell_head(btc).squeeze(-1)     # (B, n_buildings, n_cells)
        build_cell_logits = build_cell_logits.masked_fill(~buildable_cells, float('-inf'))

        # Building logits computation
        building_logits = self.building_head(global_encoded)          # (B, n_buildings)
        building_logits = building_logits.masked_fill(~available_buildings, float('-inf'))

        # Builders encoding
        builder_encoded = self.builder_encoder(builder_features)      # (B, builders, d_model)

        key_padding_mask = ~available_builders.clone()
        has_builder = available_builders.any(dim=-1)
        no_builders = ~has_builder

        if no_builders.any():
            key_padding_mask[no_builders, 0] = False

        # Attention mechanisms
        x, _ = self.builder_to_builder_attention(builder_encoded, builder_encoded, builder_encoded, key_padding_mask=key_padding_mask)

        x     = self.norm1(builder_encoded + x)

        x2, _ = self.builder_to_cell_attention(x, cell_encoded, cell_encoded)
        x     = self.norm2(x + x2)

        x3, _ = self.builder_to_global_attention(x, global_encoded.unsqueeze(1), global_encoded.unsqueeze(1))
        x     = self.norm3(x + x3)                                   # (B, n_builders, d_model)

        mask = available_builders.unsqueeze(-1)

        x_masked = x * mask

        pooled = (
            x_masked.sum(dim=1)
            /
            mask.sum(dim=1).clamp(min=1)
        ) # (B, d_model)

        # Builder logits computation with masking
        builder_logits  = self.builder_head(x).squeeze(-1)           # (B, n_builders)
        builder_logits = builder_logits.masked_fill(~available_builders, float('-inf'))

        # Action logits computation
        action_logits   = self.action_head(pooled)                    # (B, 3)

        # Move cell logits computation
        x_exp = x.unsqueeze(2).expand(-1, -1, n_cells, -1)           # (B, n_builders, n_cells, d_model)
        c_exp = cell_encoded.unsqueeze(1).expand(-1, n_builders, -1, -1)
        bc    = torch.cat([x_exp, c_exp], dim=-1)                    # (B, n_builders, n_cells, d_model*2)

        move_cell_logits = self.move_cell_head(bc).squeeze(-1)        # (B, n_builders, n_cells)
        move_cell_logits = move_cell_logits.masked_fill(~moveable_cells, float('-inf'))

        # Masking action logits based on available builders and buildings
        can_move = (
            available_builders.any(dim=-1)
            & moveable_cells.any(dim=(1,2))
        )

        action_logits[~can_move, 1] = float("-inf")

        can_build = (
            available_buildings.any(dim=-1)
            & buildable_cells.any(dim=(1,2))
        )

        action_logits[~can_build, 2] = float("-inf")

        # Value head computation
        value = self.value_head(pooled)                               # (B, 1)

        return TensorDict({
            "action_logits":     action_logits,      # (B, 3)
            "builder_logits":    builder_logits,     # (B, n_builders)
            "building_logits":   building_logits,    # (B, n_buildings)
            "move_cell_logits":  move_cell_logits,   # (B, n_builders, n_cells)
            "build_cell_logits": build_cell_logits,  # (B, n_buildings, n_cells)
            "value":             value,              # (B, 1)
        })


    def _sample_actions(self, logits):
        B = logits["action_logits"].shape[0]
        device = logits["action_logits"].device

        action_logits = logits["action_logits"].clone()

        # Safety: disable MOVE if no builder has a valid move
        can_move = (
            torch.isfinite(logits["move_cell_logits"])
            .any(dim=-1)
            &
            torch.isfinite(logits["builder_logits"])
        )
        can_move = can_move.any(dim=-1)

        action_logits[~can_move, 1] = float("-inf")

        building_can_build = torch.isfinite(
            logits["build_cell_logits"]
        ).any(dim=-1)

        can_building = torch.isfinite(
            logits["building_logits"]
        )

        can_build = (
            building_can_build
            &
            can_building
        ).any(dim=-1)

        action_logits[~can_build,2] = float("-inf")

        invalid = torch.isneginf(action_logits).all(dim=-1)
        action_logits[invalid] = 0.0


        action = Categorical(
            logits=action_logits
        ).sample()

        builder = torch.zeros(
            B,
            dtype=torch.long,
            device=device
        )

        building = torch.zeros(
            B,
            dtype=torch.long,
            device=device
        )

        cell = torch.zeros(
            B,
            dtype=torch.long,
            device=device
        )

        # MOVE
        move_idx = action == 1

        if move_idx.any():

            builder_logits = logits["builder_logits"][move_idx].clone()

            builder_can_move = torch.isfinite(
                logits["move_cell_logits"][move_idx]
            ).any(dim=-1)  # (N, builders)

            builder_logits = builder_logits.masked_fill(
                ~builder_can_move,
                float("-inf")
            )

            # safety: if somehow no builder can move
            no_valid_builder = (~builder_can_move).all(dim=-1)

            if no_valid_builder.any():
                raise RuntimeError(
                    "MOVE selected but no valid builder exists"
                )

            builder[move_idx] = Categorical(
                logits=builder_logits
            ).sample()


            selected = logits["move_cell_logits"][
                move_idx,
                builder[move_idx]
            ].clone()


            # safety: no movable cells
            no_valid_cell = torch.isneginf(selected).all(dim=-1)

            if no_valid_cell.any():
                selected[no_valid_cell] = 0.0


            cell[move_idx] = Categorical(
                logits=selected
            ).sample()

        # BUILD
        build_idx = action == 2

        if build_idx.any():

            building_logits = logits["building_logits"][build_idx].clone()

            row_building_can_build = building_can_build[build_idx]  # (N, n_buildings)

            building_logits = building_logits.masked_fill(
                ~row_building_can_build,
                float("-inf")
            )

            no_building = torch.isneginf(building_logits).all(dim=-1)

            if no_building.any():
                raise RuntimeError(
                    "BUILD selected but no valid building exists"
                )

            building[build_idx] = Categorical(
                logits=building_logits
            ).sample()


            selected = logits["build_cell_logits"][
                build_idx,
                building[build_idx]
            ].clone()


            no_valid_cell = torch.isneginf(selected).all(dim=-1)

            if no_valid_cell.any():
                raise RuntimeError(
                    "BUILD: building has no valid cell despite building_can_build mask "
                    "(this should be impossible — check build_cell_logits vs building_logits masks for inconsistency)"
                )


            cell[build_idx] = Categorical(
                logits=selected
            ).sample()

        return torch.stack(
            [
                action,
                builder,
                building,
                cell
            ],
            dim=-1
        )


    def _compute_log_prob(self, logits: TensorDict, actions: torch.Tensor) -> torch.Tensor:
        B = actions.size(0)

        action   = actions[:, 0]
        builder  = actions[:, 1]
        building = actions[:, 2]
        cell     = actions[:, 3]

        is_skip  = action == 0
        is_move  = action == 1
        is_build = action == 2

        action_lp   = Categorical(logits=logits["action_logits"]).log_prob(action)

        all_masked_builder = logits["builder_logits"].isneginf().all(dim=-1, keepdim=True)
        builder_logits = logits["builder_logits"].masked_fill(all_masked_builder, 0.0)
        builder_lp  = Categorical(logits=builder_logits).log_prob(builder)

        all_masked_building = logits["building_logits"].isneginf().all(dim=-1, keepdim=True)
        building_logits = logits["building_logits"].masked_fill(all_masked_building, 0.0)
        building_lp = Categorical(logits=building_logits).log_prob(building)

        # move cell log prob — guard against all -inf
        move_cell_logits = logits["move_cell_logits"][torch.arange(B), builder]
        all_masked_move  = move_cell_logits.isneginf().all(dim=-1, keepdim=True)
        move_cell_logits = move_cell_logits.masked_fill(all_masked_move, 0.0)
        move_cell_lp     = Categorical(logits=move_cell_logits).log_prob(cell)

        # build cell log prob — guard against all -inf
        build_cell_logits = logits["build_cell_logits"][torch.arange(B), building]
        all_masked_build  = build_cell_logits.isneginf().all(dim=-1, keepdim=True)
        build_cell_logits = build_cell_logits.masked_fill(all_masked_build, 0.0)
        build_cell_lp     = Categorical(logits=build_cell_logits).log_prob(cell)

        # entity log prob: builder for move, building for build, zero for skip
        entity_lp = torch.where(is_move,  builder_lp,
                    torch.where(is_build, building_lp,
                                torch.zeros_like(builder_lp)))

        # cell log prob: move_cell for move, build_cell for build, zero for skip
        cell_lp = torch.where(is_move,  move_cell_lp,
                torch.where(is_build, build_cell_lp,
                            torch.zeros_like(move_cell_lp)))

        return action_lp + entity_lp + cell_lp

    def forward(self, obs: TensorDict, action_mask: TensorDict | None = None) -> TensorDict:
        logits  = self._get_logits(obs, action_mask)
        actions = self._sample_actions(logits)

        log_prob = self._compute_log_prob(logits, actions)
        value    = logits["value"].squeeze(-1)

        return TensorDict({
            "action":    actions,               # TensorDict of all action components
            "log_prob":  log_prob,              # (B,)
            "value":     value,       # (B, 1)
        }, batch_size=obs.batch_size)

    def _safe_entropy(self, logits: torch.Tensor) -> torch.Tensor:
        """
        Computes entropy while protecting against all -inf logits.
        logits: (..., n_actions)
        returns: (...,)
        """
        all_masked = torch.isneginf(logits).all(dim=-1)

        # replace invalid distributions temporarily
        safe_logits = logits.clone()
        safe_logits[all_masked] = 0.0

        entropy = Categorical(logits=safe_logits).entropy()

        # invalid distributions have no entropy
        entropy[all_masked] = 0.0

        return entropy


    def evaluate(self, obs: TensorDict, actions: TensorDict, action_mask: TensorDict | None = None) -> TensorDict:
        logits = self._get_logits(obs, action_mask)

        log_probs = self._compute_log_prob(logits, actions)

        action = actions[:, 0]
        builder = actions[:, 1]
        building = actions[:, 2]

        is_move = action == 1
        is_build = action == 2

        B = action.size(0)
        batch_idx = torch.arange(B, device=action.device)

        # Action type entropy
        action_ent = self._safe_entropy(
            logits["action_logits"]
        )

        # Builder selection entropy
        builder_ent = self._safe_entropy(
            logits["builder_logits"]
        )

        # Building selection entropy
        building_ent = self._safe_entropy(
            logits["building_logits"]
        )

        # Move cell entropy
        selected_move_cells = logits["move_cell_logits"][
            batch_idx,
            builder
        ]

        move_cell_ent = self._safe_entropy(
            selected_move_cells
        )

        # Build cell entropy
        selected_build_cells = logits["build_cell_logits"][
            batch_idx,
            building
        ]

        build_cell_ent = self._safe_entropy(
            selected_build_cells
        )

        # Only include entropy of distributions actually used
        entropy = (
            action_ent
            + torch.where(is_move, builder_ent + move_cell_ent, 0.0)
            + torch.where(is_build, building_ent + build_cell_ent, 0.0)
        )

        return TensorDict({
            "log_probs": log_probs,
            "value": logits["value"].squeeze(-1),
            "entropy": entropy,
        }, batch_size=obs.batch_size)
