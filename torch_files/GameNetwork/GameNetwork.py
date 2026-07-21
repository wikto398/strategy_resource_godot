from tensordict import TensorDict
import torch
import torch.nn as nn
from torch.distributions import Categorical


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

    @staticmethod
    def _safe_logits(logits: torch.Tensor) -> torch.Tensor:
        """Make logits safe for Categorical: replace non-finite with -inf, all-masked rows -> 0."""
        safe = torch.where(torch.isfinite(logits), logits, torch.full_like(logits, float("-inf")))
        all_masked = torch.isneginf(safe).all(dim=-1, keepdim=True)
        return safe.masked_fill(all_masked, 0.0)

    def _categorical(self, logits: torch.Tensor) -> Categorical:
        return Categorical(logits=self._safe_logits(logits))

    def _get_logits(self, obs: TensorDict, action_mask: TensorDict | None) -> TensorDict:
        cell_features    = obs["fields"]    # (B, cells, cell_features)
        global_features  = obs["global"]   # (B, global_features)
        builder_features = obs["builders"] # (B, builders, builder_features)
        B = cell_features.size(0)
        n_builders = builder_features.size(1)
        n_buildings = self.n_buildings
        n_cells = cell_features.size(1)

        device = cell_features.device

        moveable_cells      = action_mask["moveable_cells"]      if action_mask is not None else torch.ones((B, n_builders, n_cells), dtype=torch.bool, device=device)
        buildable_cells     = action_mask["buildable_cells"]     if action_mask is not None else torch.ones((B, n_buildings, n_cells), dtype=torch.bool, device=device)
        available_buildings = action_mask["available_buildings"] if action_mask is not None else torch.ones((B, n_buildings), dtype=torch.bool, device=device)
        available_builders  = action_mask["available_builders"]  if action_mask is not None else torch.ones((B, n_builders), dtype=torch.bool, device=device)

        available_builders = available_builders.bool()
        available_buildings = available_buildings.bool()
        moveable_cells = moveable_cells.bool()
        buildable_cells = buildable_cells.bool()

        builder_can_move = available_builders & moveable_cells.any(dim=-1)          # (B, n_builders)
        building_can_build = available_buildings & buildable_cells.any(dim=-1)      # (B, n_buildings)
        can_move = builder_can_move.any(dim=-1)                                     # (B,)
        can_build = building_can_build.any(dim=-1)                                   # (B,)

        cell_encoded   = self.cell_encoder(cell_features)              # (B, cells, d_model)
        global_encoded = self.global_encoder(global_features)          # (B, d_model)

        bt = self.building_encoder(torch.arange(n_buildings, device=device))  # (n_buildings, d_model)
        bt = bt.unsqueeze(0).expand(B, -1, -1)  # (B, n_buildings, d_model)

        g_exp = global_encoded[:, None, None, :].expand(B, n_buildings, n_cells, -1)
        bt_exp = bt.unsqueeze(2).expand(-1, -1, n_cells, -1)
        c_exp2 = cell_encoded.unsqueeze(1).expand(-1, self.n_buildings, -1, -1)
        btc = torch.cat([bt_exp, c_exp2, g_exp], dim=-1)
        build_cell_logits = self.build_cell_head(btc).squeeze(-1)
        build_cell_logits = build_cell_logits.masked_fill(~buildable_cells, float("-inf"))

        building_logits = self.building_head(global_encoded)
        building_logits = building_logits.masked_fill(~building_can_build, float("-inf"))

        builder_encoded = self.builder_encoder(builder_features)

        key_padding_mask = ~available_builders
        no_builders = key_padding_mask.all(dim=-1)
        if no_builders.any():
            key_padding_mask = key_padding_mask.clone()
            key_padding_mask[no_builders, 0] = False

        x, _ = self.builder_to_builder_attention(
            builder_encoded, builder_encoded, builder_encoded,
            key_padding_mask=key_padding_mask,
        )
        x = self.norm1(builder_encoded + x)

        x2, _ = self.builder_to_cell_attention(x, cell_encoded, cell_encoded)
        x = self.norm2(x + x2)

        x3, _ = self.builder_to_global_attention(
            x, global_encoded.unsqueeze(1), global_encoded.unsqueeze(1)
        )
        x = self.norm3(x + x3)

        x = torch.where(torch.isfinite(x), x, torch.zeros_like(x))

        pool_mask = available_builders.unsqueeze(-1).float()
        pooled = x.mul(pool_mask).sum(dim=1) / pool_mask.sum(dim=1).clamp(min=1.0)

        builder_logits = self.builder_head(x).squeeze(-1)
        builder_logits = builder_logits.masked_fill(~builder_can_move, float("-inf"))

        action_logits = self.action_head(pooled)
        action_logits = torch.stack(
            [
                action_logits[:, 0],
                action_logits[:, 1].masked_fill(~can_move, float("-inf")),
                action_logits[:, 2].masked_fill(~can_build, float("-inf")),
            ],
            dim=-1,
        )

        x_exp = x.unsqueeze(2).expand(-1, -1, n_cells, -1)
        c_exp = cell_encoded.unsqueeze(1).expand(-1, n_builders, -1, -1)
        bc = torch.cat([x_exp, c_exp], dim=-1)
        move_cell_logits = self.move_cell_head(bc).squeeze(-1)
        move_cell_logits = move_cell_logits.masked_fill(~moveable_cells, float("-inf"))

        value = self.value_head(pooled)

        return TensorDict({
            "action_logits":     action_logits,
            "builder_logits":    builder_logits,
            "building_logits":   building_logits,
            "move_cell_logits":  move_cell_logits,
            "build_cell_logits": build_cell_logits,
            "value":             value,
        })

    def _sample_actions(self, logits):
        B = logits["action_logits"].shape[0]
        device = logits["action_logits"].device

        # Logits already carry consistent masks from _get_logits.
        action = self._categorical(logits["action_logits"]).sample()

        builder = torch.zeros(B, dtype=torch.long, device=device)
        building = torch.zeros(B, dtype=torch.long, device=device)
        cell = torch.zeros(B, dtype=torch.long, device=device)

        move_idx = action == 1
        if move_idx.any():
            builder_logits = logits["builder_logits"][move_idx]
            builder[move_idx] = self._categorical(builder_logits).sample()
            selected = logits["move_cell_logits"][move_idx, builder[move_idx]]
            cell[move_idx] = self._categorical(selected).sample()

        build_idx = action == 2
        if build_idx.any():
            building_logits = logits["building_logits"][build_idx]
            building[build_idx] = self._categorical(building_logits).sample()
            selected = logits["build_cell_logits"][build_idx, building[build_idx]]
            cell[build_idx] = self._categorical(selected).sample()

        return torch.stack([action, builder, building, cell], dim=-1)

    def _compute_log_prob(self, logits: TensorDict, actions: torch.Tensor) -> torch.Tensor:
        B = actions.size(0)
        batch_idx = torch.arange(B, device=actions.device)

        action   = actions[:, 0]
        builder  = actions[:, 1]
        building = actions[:, 2]
        cell     = actions[:, 3]

        is_move  = action == 1
        is_build = action == 2

        # Same logits / masks as sampling — no extra sample-only masking.
        action_lp   = self._categorical(logits["action_logits"]).log_prob(action)
        builder_lp  = self._categorical(logits["builder_logits"]).log_prob(builder)
        building_lp = self._categorical(logits["building_logits"]).log_prob(building)
        move_cell_lp = self._categorical(
            logits["move_cell_logits"][batch_idx, builder]
        ).log_prob(cell)
        build_cell_lp = self._categorical(
            logits["build_cell_logits"][batch_idx, building]
        ).log_prob(cell)

        entity_lp = torch.where(
            is_move, builder_lp,
            torch.where(is_build, building_lp, torch.zeros_like(builder_lp)),
        )
        cell_lp = torch.where(
            is_move, move_cell_lp,
            torch.where(is_build, build_cell_lp, torch.zeros_like(move_cell_lp)),
        )

        return action_lp + entity_lp + cell_lp

    def forward(self, obs: TensorDict, action_mask: TensorDict | None = None) -> TensorDict:
        logits  = self._get_logits(obs, action_mask)
        actions = self._sample_actions(logits)
        log_prob = self._compute_log_prob(logits, actions)
        value    = logits["value"].squeeze(-1)

        return TensorDict({
            "action":   actions,
            "log_prob": log_prob,
            "value":    value,
        }, batch_size=obs.batch_size)

    def _safe_entropy(self, logits: torch.Tensor) -> torch.Tensor:
        all_masked = ~torch.isfinite(logits).any(dim=-1)
        entropy = self._categorical(logits).entropy()
        entropy = entropy.masked_fill(all_masked, 0.0)
        return entropy

    def evaluate(self, obs: TensorDict, actions: torch.Tensor, action_mask: TensorDict | None = None) -> TensorDict:
        logits = self._get_logits(obs, action_mask)
        log_probs = self._compute_log_prob(logits, actions)

        action = actions[:, 0]
        builder = actions[:, 1]
        building = actions[:, 2]

        is_move = action == 1
        is_build = action == 2

        B = action.size(0)
        batch_idx = torch.arange(B, device=action.device)

        action_ent = self._safe_entropy(logits["action_logits"])
        builder_ent = self._safe_entropy(logits["builder_logits"])
        building_ent = self._safe_entropy(logits["building_logits"])
        move_cell_ent = self._safe_entropy(logits["move_cell_logits"][batch_idx, builder])
        build_cell_ent = self._safe_entropy(logits["build_cell_logits"][batch_idx, building])

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
