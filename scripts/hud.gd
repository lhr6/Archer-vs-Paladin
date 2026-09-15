extends CanvasLayer
## 玩家 HUD：左下角血条，自动连接玩家 Health 组件；右上角倍速指示（F 切换 1x/2x）

@onready var hp_bar: ProgressBar = $MarginContainer/PanelContainer/VBoxContainer/ProgressBar
@onready var speed_label: Label = $SpeedLabel

func _ready() -> void:
	# 倍速指示：跟随全局 SpeedMode（按 F 切换 1x/2x）
	SpeedMode.factor_changed.connect(_on_speed_mode_changed)
	_update_speed_label(SpeedMode.factor)
	# 等一帧确保玩家场景就绪
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_node("Health"):
		player.get_node("Health").health_changed.connect(_on_health_changed)

func _on_speed_mode_changed(factor: float) -> void:
	_update_speed_label(factor)

func _update_speed_label(factor: float) -> void:
	if factor > 1.0:
		var s := String.num(factor)
		speed_label.text = (s.trim_suffix(".0") if s.ends_with(".0") else s) + "x 加速中（F 切换）"
		speed_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	else:
		speed_label.text = "F：倍速切换"
		speed_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.75))

func _on_health_changed(current: float, maximum: float) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	# 低血量时填充变红
	var ratio: float = current / maximum
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.18, 0.14) if ratio < 0.3 else Color(0.2, 0.72, 0.28)
	fill.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("fill", fill)
