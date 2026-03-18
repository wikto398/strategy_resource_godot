class_name WinConditionSpecial extends Special

func activate() -> void:
	DebugLogger.info("Win condition activated! Check if the player has met the win condition.".format({}))
	Global.win_conditions_met += 1
