"""torch.compile equivalence gate for the strategy network.

Checks that wrapping the GameNetwork in torch.compile preserves the network's
deterministic outputs (log_probs / value / entropy for fixed actions) within a
small tolerance, that compiled sampling is self-deterministic for a fixed seed,
and reports a forward-pass speedup. Exits non-zero on any failure so it can be
used as a pre-enable gate for `--torch_compile`.

Run from the repo root:
    PYTHONPATH=. rl_tools/.venv/bin/python tools/check_compile_equivalence.py
"""

import copy
import sys
import time

import numpy as np
import torch

from torch_files.Factory import StrategyNetworkFactory

TOL = 1e-3
N = 8
N_CELLS = 192
N_BUILDINGS = 10


def make_batch(no_mask: bool = False, all_builders_masked: bool = False):
    from tensordict import TensorDict

    rng = np.random.RandomState(0)
    fields = np.zeros((N, N_CELLS, 7), dtype=np.float32)
    fields[..., 0] = rng.randint(0, 3, (N, N_CELLS))
    fields[..., 1] = 1
    fields[..., 2] = rng.randint(0, N_BUILDINGS, (N, N_CELLS))
    fields[..., 6] = rng.rand(N, N_CELLS)
    g = np.zeros((N, 15), dtype=np.float32)
    g[..., :4] = rng.randint(0, 40, (N, 4))
    g[..., 4:8] = rng.randint(0, 2000, (N, 4))
    g[..., 8:15] = 1
    builders = np.zeros((N, 5, 6), dtype=np.float32)
    builders[..., :2] = rng.randint(0, 15, (N, 5, 2))
    builders[..., 5] = 1

    obs = TensorDict(
        {
            "fields": torch.from_numpy(fields),
            "global": torch.from_numpy(g),
            "builders": torch.from_numpy(builders),
        },
        batch_size=[N],
    )
    if no_mask:
        return obs, None

    ab = np.ones((N, 5), dtype=bool)
    rb = np.ones((N, 5), dtype=bool)
    if all_builders_masked:
        ab[:] = False
    masks = TensorDict(
        {
            "buildable_cells": torch.from_numpy(
                rng.randint(0, 2, (N, N_BUILDINGS, N_CELLS)).astype(bool)
            ),
            "available_buildings": torch.from_numpy(
                rng.randint(0, 2, (N, N_BUILDINGS)).astype(bool)
            ),
            "moveable_cells": torch.from_numpy(
                rng.randint(0, 2, (N, 5, N_CELLS)).astype(bool)
            ),
            "available_builders": torch.from_numpy(ab),
            "real_builders": torch.from_numpy(rb),
            "available_skip": torch.ones((N,), dtype=torch.bool),
        },
        batch_size=[N],
    )
    return obs, masks


def max_diff(a, b):
    a = a.float() if a.dtype == torch.bool else a
    b = b.float() if b.dtype == torch.bool else b
    return (a - b).abs().max().item()


def compare_evaluate(net, compiled, obs, mask, actions, label):
    out = net.evaluate(obs, actions, mask)
    c_out = compiled.evaluate(obs, actions, mask)
    worst = 0.0
    for key in ("log_probs", "value", "entropy"):
        d = max_diff(out[key], c_out[key])
        worst = max(worst, d)
    status = "PASS" if worst < TOL else "FAIL"
    print(f"  [{status}] {label}: max|diff|={worst:.2e} (tol {TOL})")
    return worst < TOL


def main():
    if not torch.cuda.is_available():
        print("SKIP: no CUDA device available (torch.compile requires CUDA)")
        return 0

    torch.manual_seed(0)
    np.random.seed(0)

    net = StrategyNetworkFactory.instance().build().to("cuda").eval()
    compiled = torch.compile(copy.deepcopy(net)).eval()

    cases = [
        ("normal", *make_batch()),
        ("no_mask", *make_batch(no_mask=True)),
        ("all_builders_masked", *make_batch(all_builders_masked=True)),
    ]

    ok = True
    for label, obs, mask in cases:
        obs = obs.to("cuda")
        if mask is not None:
            mask = mask.to("cuda")
        try:
            torch.manual_seed(2)
            actions = net.forward(obs, mask)["action"]
            ok &= compare_evaluate(net, compiled, obs, mask, actions, label)
        except Exception as e:  # trace / compile failure
            ok = False
            print(f"  [FAIL] {label}: trace error: {type(e).__name__}: {e}")

    # Compiled sampling must be self-deterministic for a fixed seed.
    obs, mask = make_batch()
    obs = obs.to("cuda")
    if mask is not None:
        mask = mask.to("cuda")
    torch.manual_seed(3)
    a1 = compiled.forward(obs, mask)["action"].clone()
    torch.manual_seed(3)
    a2 = compiled.forward(obs, mask)["action"].clone()
    self_det = torch.equal(a1, a2)
    print(f"  [{('PASS' if self_det else 'FAIL')}] compiled self-determinism")
    ok &= self_det

    # Timing (compiled warmup already happened above).
    with torch.no_grad():
        for _ in range(5):
            net(obs, mask)
        torch.cuda.synchronize()
        t0 = time.perf_counter()
        for _ in range(100):
            net(obs, mask)
        torch.cuda.synchronize()
        t_uncompiled = (time.perf_counter() - t0) / 100 * 1000

        for _ in range(5):
            compiled(obs, mask)
        torch.cuda.synchronize()
        t0 = time.perf_counter()
        for _ in range(100):
            compiled(obs, mask)
        torch.cuda.synchronize()
        t_compiled = (time.perf_counter() - t0) / 100 * 1000

    print(
        f"forward timing: uncompiled {t_uncompiled:.2f} ms | "
        f"compiled {t_compiled:.2f} ms | speedup {t_uncompiled / max(t_compiled, 1e-9):.2f}x"
    )

    print(f"OVERALL: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
