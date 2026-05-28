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
        self.build_cell_head = nn.Linear(d_model * 2, 1)
        self.value_head = nn.Linear(d_model, 1)

    def _get_logits(self, obs: TensorDict, action_mask: TensorDict | None) -> TensorDict:
        cell_features    = obs["fields"]    # (B, cells, cell_features)
        global_features  = obs["global"]   # (B, global_features)
        builder_features = obs["builders"] # (B, builders, builder_features)

        moveable_cells      = action_mask["moveable_cells"]      if action_mask is not None else None  # (B, builders, cells)
        buildable_cells     = action_mask["buildable_cells"]     if action_mask is not None else None  # (B, n_buildings, cells)
        available_buildings = action_mask["available_buildings"] if action_mask is not None else None  # (B, n_buildings)

        B       = cell_features.size(0)
        n_cells = cell_features.size(1)
        device  = cell_features.device

        cell_encoded   = self.cell_encoder(cell_features)              # (B, cells, d_model)
        global_encoded = self.global_encoder(global_features)          # (B, d_model)

        # --- building cell scores (never depend on builders) ---
        building_idx = torch.arange(self.n_buildings, device=device)
        bt    = self.building_encoder(building_idx)                    # (n_buildings, d_model)
        bt    = bt.unsqueeze(0).expand(B, -1, -1)                     # (B, n_buildings, d_model)

        bt_exp = bt.unsqueeze(2).expand(-1, -1, n_cells, -1)          # (B, n_buildings, n_cells, d_model)
        c_exp2 = cell_encoded.unsqueeze(1).expand(-1, self.n_buildings, -1, -1)
        btc    = torch.cat([bt_exp, c_exp2], dim=-1)                  # (B, n_buildings, n_cells, d_model*2)
        build_cell_logits = self.build_cell_head(btc).squeeze(-1)     # (B, n_buildings, n_cells)

        if buildable_cells is not None:
            build_cell_logits = build_cell_logits.masked_fill(~buildable_cells, float('-inf'))

        building_logits = self.building_head(global_encoded)          # (B, n_buildings)
        if available_buildings is not None:
            building_logits = building_logits.masked_fill(~available_buildings, float('-inf'))

        # --- no builders case ---
        n_builders = builder_features.size(1)
        if n_builders == 0:
            action_logits = torch.zeros(B, 3, device=device)
            action_logits[:, 1] = float('-inf')   # move impossible

            # mask build if no buildings available either
            if available_buildings is not None:
                no_buildings = (~available_buildings).all(dim=-1)     # (B,)
                action_logits[no_buildings, 2] = float('-inf')        # build impossible too

            return TensorDict({
                "action_logits":     action_logits,                                        # (B, 3)
                "builder_logits":    torch.zeros(B, 1, device=device),                    # dummy
                "building_logits":   building_logits,                                     # (B, n_buildings)
                "move_cell_logits":  torch.full((B, 1, n_cells), float('-inf'), device=device),  # dummy
                "build_cell_logits": build_cell_logits,                                   # (B, n_buildings, n_cells)
                "value":             self.value_head(global_encoded),                     # (B, 1)
            })

        # --- normal path: builders exist ---
        builder_encoded = self.builder_encoder(builder_features)      # (B, builders, d_model)

        x, _ = self.builder_to_builder_attention(builder_encoded, builder_encoded, builder_encoded)
        x     = self.norm1(builder_encoded + x)

        x2, _ = self.builder_to_cell_attention(x, cell_encoded, cell_encoded)
        x     = self.norm2(x + x2)

        x3, _ = self.builder_to_global_attention(x, global_encoded.unsqueeze(1), global_encoded.unsqueeze(1))
        x     = self.norm3(x + x3)                                   # (B, n_builders, d_model)

        pooled = x.mean(dim=1)                                        # (B, d_model)

        action_logits   = self.action_head(pooled)                    # (B, 3)
        builder_logits  = self.builder_head(x).squeeze(-1)           # (B, n_builders)

        # mask build if no buildings available
        if available_buildings is not None:
            no_buildings = (~available_buildings).all(dim=-1)         # (B,)
            action_logits[no_buildings, 2] = float('-inf')

        # move cell scores per builder
        x_exp = x.unsqueeze(2).expand(-1, -1, n_cells, -1)           # (B, n_builders, n_cells, d_model)
        c_exp = cell_encoded.unsqueeze(1).expand(-1, n_builders, -1, -1)
        bc    = torch.cat([x_exp, c_exp], dim=-1)                    # (B, n_builders, n_cells, d_model*2)

        move_cell_logits = self.move_cell_head(bc).squeeze(-1)        # (B, n_builders, n_cells)

        if moveable_cells is not None:
            move_cell_logits = move_cell_logits.masked_fill(~moveable_cells, float('-inf'))

            # if ALL cells are masked for a builder, that builder can't move
            # if ALL builders can't move, mask the move action entirely
            any_moveable = moveable_cells.any(dim=-1)        # (B, n_builders) — does builder have any valid cell?
            any_builder_can_move = any_moveable.any(dim=-1)  # (B,) — can any builder move?
            action_logits[~any_builder_can_move, 1] = float('-inf')

        # same for build
        if buildable_cells is not None:
            any_buildable = buildable_cells.any(dim=-1)          # (B, n_buildings)
            any_building_can_build = any_buildable.any(dim=-1)   # (B,)
            action_logits[~any_building_can_build, 2] = float('-inf')

        value = self.value_head(pooled)                               # (B, 1)

        return TensorDict({
            "action_logits":     action_logits,      # (B, 3)
            "builder_logits":    builder_logits,     # (B, n_builders)
            "building_logits":   building_logits,    # (B, n_buildings)
            "move_cell_logits":  move_cell_logits,   # (B, n_builders, n_cells)
            "build_cell_logits": build_cell_logits,  # (B, n_buildings, n_cells)
            "value":             value,              # (B, 1)
        })

    def _sample_actions(self, logits: TensorDict) -> torch.Tensor:
        action_dist   = Categorical(logits=logits["action_logits"])
        builder_dist  = Categorical(logits=logits["builder_logits"])
        building_dist = Categorical(logits=logits["building_logits"])

        action   = action_dist.sample()    # (B,)
        builder  = builder_dist.sample()   # (B,)
        building = building_dist.sample()  # (B,)

        B = action.size(0)

        # gather selected builder's move cell logits
        move_logits          = logits["move_cell_logits"]                    # (B, n_builders, n_cells)
        selected_move_logits = move_logits[torch.arange(B), builder]         # (B, n_cells)

        # guard: if all -inf (dummy or no valid cells), replace with zeros so Categorical doesn't nan
        all_masked_move      = selected_move_logits.isinf().all(dim=-1, keepdim=True)
        selected_move_logits = selected_move_logits.masked_fill(all_masked_move, 0.0)
        move_cell            = Categorical(logits=selected_move_logits).sample()   # (B,)

        # gather selected building's build cell logits
        build_logits          = logits["build_cell_logits"]                   # (B, n_buildings, n_cells)
        selected_build_logits = build_logits[torch.arange(B), building]       # (B, n_cells)

        # guard: same as above
        all_masked_build      = selected_build_logits.isinf().all(dim=-1, keepdim=True)
        selected_build_logits = selected_build_logits.masked_fill(all_masked_build, 0.0)
        build_cell            = Categorical(logits=selected_build_logits).sample()  # (B,)

        # pick cell based on action type
        cell = torch.where(action == 1, move_cell, build_cell)               # (B,)

        actions = torch.stack([action, builder, building, cell], dim=-1)  # (B, 4)
        return actions


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
        builder_lp  = Categorical(logits=logits["builder_logits"]).log_prob(builder)
        building_lp = Categorical(logits=logits["building_logits"]).log_prob(building)

        # move cell log prob — guard against all -inf
        move_cell_logits = logits["move_cell_logits"][torch.arange(B), builder]
        all_masked_move  = move_cell_logits.isinf().all(dim=-1, keepdim=True)
        move_cell_logits = move_cell_logits.masked_fill(all_masked_move, 0.0)
        move_cell_lp     = Categorical(logits=move_cell_logits).log_prob(cell)

        # build cell log prob — guard against all -inf
        build_cell_logits = logits["build_cell_logits"][torch.arange(B), building]
        all_masked_build  = build_cell_logits.isinf().all(dim=-1, keepdim=True)
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

        return TensorDict({
            "action":    actions,               # TensorDict of all action components
            "log_prob":  log_prob,              # (B,)
            "value":     logits["value"],       # (B, 1)
        }, batch_size=obs.batch_size)

    def evaluate(self, obs: TensorDict, actions: TensorDict, action_mask: TensorDict | None = None) -> TensorDict:
        logits = self._get_logits(obs, action_mask)

        log_probs = self._compute_log_prob(logits, actions)

        # entropy — sum over all sub-distributions
        action_ent   = Categorical(logits=logits["action_logits"]).entropy()
        builder_ent  = Categorical(logits=logits["builder_logits"]).entropy()
        building_ent = Categorical(logits=logits["building_logits"]).entropy()
        entropy = action_ent + builder_ent + building_ent   # (B,)

        return TensorDict({
            "log_probs": log_probs,
            "value":     logits["value"],
            "entropy":   entropy,
        }, batch_size=obs.batch_size)
