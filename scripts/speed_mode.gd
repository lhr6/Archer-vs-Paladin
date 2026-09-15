extends Node
## 全局倍速模式（多档切换）
## 按 Tab 键在 1x / 1.5x / 2x 之间循环切换；所有读取 SpeedMode.factor 的
## 动画播放速度、移动速度、重力、跳跃与计时都会统一乘倍，
## 让整个游戏节奏整体翻倍，而不是只加速某一个动画。

signal factor_changed(factor: float)

## 档位列表：Tab 键按顺序循环
const LEVELS: Array[float] = [1.0, 1.5, 2.0]

var factor: float = LEVELS[0]
var _level: int = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle()

func toggle() -> void:
	_level = (_level + 1) % LEVELS.size()
	factor = LEVELS[_level]
	factor_changed.emit(factor)
	print("[SpeedMode] 游戏倍速 = ", factor, "x")

func scale(v: float) -> float:
	return v * factor
