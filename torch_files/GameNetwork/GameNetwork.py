from tensordict import TensorDict
import torch
import torch.nn as nn
from torch.distributions import Categorical
import numpy as np

class GameNetwork(nn.Module):
    def __init__(self, n_cells, cell_features, n_global_features, n_buildings, n_cells_out):
        super().__init__()

        self.field_encoder = nn.Sequential(
            nn.Linear(n_cells * cell_features, 256),
            nn.ReLU(),
            nn.Linear(256, 128),
            nn.ReLU(),
        )

        self.global_encoder = nn.Sequential(
            nn.Linear(n_global_features, 32),
            nn.ReLU(),
        )

        self.combined_encoder = nn.Sequential(
            nn.Linear(128 + 32, 128),
            nn.ReLU(),
        )

        self.building_head = nn.Linear(128, n_buildings)
        self.building_embed = nn.Embedding(n_buildings, 16)
        self.cell_head = nn.Linear(128 + 16, n_cells_out)
        self.value_head = nn.Linear(128, 1)

    @property
    def device(self) -> torch.device:
        return next(self.parameters()).device

    def forward(self, obs, action_mask=None) -> TensorDict:
        """Used during rollout collection — samples actions."""
        encoded = self._get_combined_encoding(obs)
        building_mask, cell_mask = self._get_separate_action_masks(action_mask)

        building_logits = self.building_head(encoded)
        if building_mask is not None:
            building_logits[~building_mask] = -1e9

        building_dist = Categorical(logits=building_logits)
        building_action = building_dist.sample()
        building_emb = self.building_embed(building_action)

        cell_logits = self.cell_head(torch.cat([encoded, building_emb], dim=-1))
        if cell_mask is not None:
            chosen_cell_mask = cell_mask[torch.arange(cell_mask.shape[0]), building_action]
            cell_logits[~chosen_cell_mask] = -1e9

        cell_dist = Categorical(logits=cell_logits)
        cell_action = cell_dist.sample()
        log_prob = building_dist.log_prob(building_action) + cell_dist.log_prob(cell_action)
        value = self.value_head(encoded)

        return TensorDict({
            "action": torch.stack([building_action, cell_action], dim=-1),
            "log_prob": log_prob,
            "value": value.squeeze(-1),
        })

    def evaluate(self, obs, building_actions: torch.Tensor, cell_actions: torch.Tensor, action_mask=None) -> TensorDict:
        """Used during PPO update — recomputes log probs for stored actions."""
        encoded = self._get_combined_encoding(obs)
        building_mask, cell_mask = self._get_separate_action_masks(action_mask)

        building_logits = self.building_head(encoded)
        if building_mask is not None:
            building_logits[~building_mask] = -1e9

        # use stored building actions — not a fresh sample
        building_emb = self.building_embed(building_actions)
        cell_logits = self.cell_head(torch.cat([encoded, building_emb], dim=-1))
        if cell_mask is not None:
            chosen_cell_mask = cell_mask[torch.arange(cell_mask.shape[0]), building_actions]
            cell_logits[~chosen_cell_mask] = -1e9

        building_dist = Categorical(logits=building_logits)
        cell_dist = Categorical(logits=cell_logits)

        log_probs = building_dist.log_prob(building_actions) + cell_dist.log_prob(cell_actions)
        entropy = building_dist.entropy() + cell_dist.entropy()
        value = self.value_head(encoded)

        return TensorDict({
            "log_probs": log_probs,
            "entropy": entropy,
            "value": value.squeeze(-1),
        }, batch_size=log_probs.shape)

    def get_action(self, obs, action_mask=None):
        building_logits, cell_logits, building_action, value = self.forward(obs, action_mask)

        building_dist = Categorical(logits=building_logits)
        cell_dist = Categorical(logits=cell_logits)

        cell_action = cell_dist.sample()
        log_prob = building_dist.log_prob(building_action) + cell_dist.log_prob(cell_action)

        return building_action, cell_action, log_prob, value.squeeze()

    def _get_combined_encoding(self, obs: TensorDict) -> torch.Tensor:
        fields = obs["fields"].flatten(start_dim=0)
        global_stats = obs["global"]

        field_encoded = self.field_encoder(fields)
        global_encoded = self.global_encoder(global_stats)
        return self.combined_encoder(
            torch.cat([field_encoded, global_encoded], dim=-1)
        )

    def _get_separate_action_masks(self, action_mask: TensorDict | None):
        if action_mask is None:
            return None, None
        building_mask = action_mask["available_buildings"]
        cell_mask = action_mask["available_cells"]
        return building_mask, cell_mask
