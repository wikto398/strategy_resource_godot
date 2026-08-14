extends Node

const KEYS: Array[String] = [
    "gamma", "stock_warning_threshold", "stock_warning_coef",
    "deficit_coef", "deficit_cap", "production_penalty_cap",
    "production_penalty_coef", "economy_coef", "balance_coef",
    "gap_target", "gap_cap", "gap_coef", "productive_bonus",
    "construction_bonus", "first_build_bonus", "win_progress_coef",
    "over_commit_penalty", "over_commit_state_penalty", "win_bonus", "loss_penalty",
    "loss_survival_horizon", "pop_milestone_bonus", "stock_milestone_bonus",
    "surplus_coef", "surplus_target", "surplus_stock_ratio", "surplus_stock_floor", "surplus_cap",
    "economy_cap", "peak_coef", "build_start_coef", "build_finish_coef",
    "build_finish_flat", "housing_coef", "skip_penalty", "time_penalty",
    "production_bonus_coef",
]

var gamma: float = 0.99
var stock_warning_threshold: float = 100.0
var stock_warning_coef: float = 0.02
var deficit_coef: float = 0.015
var deficit_cap: float = 5.0
var production_penalty_cap: float = 10.0
var production_penalty_coef: float = 0.01
var economy_coef: float = 0.05
var balance_coef: float = 0.2
var gap_target: float = 10.0
var gap_cap: float = 10.0
var gap_coef: float = 0.05
var productive_bonus: float = 0.3
var construction_bonus: float = 0.2
var first_build_bonus: float = 3.0
var build_start_coef: float = 0.1
var build_finish_coef: float = 0.15
var build_finish_flat: float = 5.0
var housing_coef: float = 1.0
var skip_penalty: float = -0.02
var time_penalty: float = -0.005
var production_bonus_coef: float = 0.3
var win_progress_coef: float = 0.005
var over_commit_penalty: float = 0.25
var over_commit_state_penalty: float = 0.1
var win_bonus: float = 50.0
var loss_penalty: float = -10.0
var loss_survival_horizon: float = 200.0
var pop_milestone_bonus: float = 1.5
var stock_milestone_bonus: float = 1.0
var surplus_coef: float = 0.05
var surplus_target: float = 10.0
var surplus_stock_ratio: float = 2.0
var surplus_stock_floor: float = 2000.0
var surplus_cap: float = 10.0
var economy_cap: float = 10.0
var peak_coef: float = 0.02

func _ready() -> void:
    for key in KEYS:
        if not ArgsParser.kwargs.has(key):
            continue
        var raw = ArgsParser.kwargs[key]
        var value: float
        if raw is String and raw.is_valid_float():
            value = raw.to_float()
        elif raw is int:
            value = float(raw)
        elif raw is float:
            value = raw
        else:
            DebugLogger.warning("RewardConfig: ignoring invalid value for '%s': %s" % [key, str(raw)])
            continue
        set(key, value)
    DebugLogger.debug("RewardConfig loaded: " + str(_snapshot()))

func _snapshot() -> Dictionary:
    var snapshot: Dictionary = {}
    for key in KEYS:
        snapshot[key] = get(key)
    return snapshot
