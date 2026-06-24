extends RefCounted
class_name RaceVisuals

const CELEBRATION_COLORS: Array[String] = ["#45d9ff", "#ff5c8a", "#ffd166", "#79e36a", "#b58cff"]
const TIMED_EFFECTS: Array[String] = ["speed", "slow", "confused", "frozen"]


static func effect_label(effect_name: String) -> String:
	var labels := {
		"speed": "TURBO",
		"slow": "RALENTI",
		"confused": "COMMANDES INVERSEES",
		"frozen": "GELE",
		"shield": "BOUCLIER",
	}
	return str(labels.get(effect_name, effect_name.to_upper()))


static func power_down_color(effect_name: String) -> Color:
	var colors := {
		"slow": "9b64e8",
		"confused": "ff5ca8",
		"frozen": "8fe7ff",
	}
	return Color(str(colors.get(effect_name, "83e8ff")))


static func power_event_color(kind: String) -> Color:
	if kind == "shield":
		return Color("ffd166")
	if kind == "slow_all" or kind == "confuse_all":
		return Color("b58cff")
	if kind == "freeze_all":
		return Color("8fe7ff")
	return Color("83e8ff")


static func text_color_for_background(color: Color) -> Color:
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return Color("07101b") if luminance > 0.58 else Color.WHITE


static func power_event_tone(kind: String) -> Dictionary:
	if kind == "speed":
		return {
			"frequency": 420.0,
			"duration": 0.2,
			"volume": 0.18,
			"waveform": "square",
			"slide": 380.0,
		}
	if kind == "shield":
		return {
			"frequency": 660.0,
			"duration": 0.24,
			"volume": 0.15,
			"waveform": "sine",
			"slide": 220.0,
		}
	return {
		"frequency": 180.0,
		"duration": 0.28,
		"volume": 0.15,
		"waveform": "square",
		"slide": -80.0,
	}
