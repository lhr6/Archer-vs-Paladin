extends Node
## 通用血量组件：挂在玩家和敌人身上，负责掉血/回血/死亡信号

signal health_changed(current: float, maximum: float)
signal died
## 受伤信号：kind 用于区分受击类型，播不同的受击动作
##   &"melee"  = 近战（拳头/剑）
##   &"ranged" = 远程（箭）
signal took_damage(amount: float, kind: StringName)

@export var max_hp: float = 100.0
var hp: float = 100.0

func _ready() -> void:
	hp = max_hp
	health_changed.emit(hp, max_hp)

func take_damage(amount: float, kind: StringName = &"") -> void:
	if hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, max_hp)
	# 先发受击（播硬直动作），再判断是否死亡（死亡动画随后覆盖）
	took_damage.emit(amount, kind)
	if hp <= 0.0:
		died.emit()

func heal(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = minf(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)
