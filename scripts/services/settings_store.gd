extends Node
class_name SettingStore

const SETTINGS_PATH := "user://settings.cfg"


func load_wall_shake_enabled(default_value: bool = true) -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return default_value
	return bool(config.get_value("accessibility", "wall_shake_enabled", default_value))


func save_wall_shake_enabled(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("accessibility", "wall_shake_enabled", enabled)
	config.save(SETTINGS_PATH)
