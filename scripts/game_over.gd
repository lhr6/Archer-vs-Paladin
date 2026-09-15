extends CanvasLayer
## 结束界面：全屏压暗 + 红色大字（YOU WIN / YOU DIE）+ 重新开始按钮。
##
## 由死亡方调用 GameOver.show_result(win)：玩家死 → false，场上敌人全灭 → true。
## 弹出时整局暂停（角色动作定格），本节点用 PROCESS_MODE_ALWAYS 才能在暂停下继续响应点击。

const WIN_TEXT := "YOU WIN"
const LOSE_TEXT := "YOU DIE"
const WIN_SUB := "敌人已全部倒下"
const LOSE_SUB := "你被击倒了"

@onready var title: Label = $Center/Panel/Margin/VBox/Title
@onready var sub: Label = $Center/Panel/Margin/VBox/Sub
@onready var restart_button: Button = $Center/Panel/Margin/VBox/RestartButton

func _ready() -> void:
	add_to_group("gameover")
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停中也能点按钮
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # 死亡时鼠标可能还锁着，放开好点按钮
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)
		restart_button.grab_focus()

func setup(win: bool) -> void:
	if title != null:
		title.text = WIN_TEXT if win else LOSE_TEXT
	if sub != null:
		sub.text = WIN_SUB if win else LOSE_SUB

func _on_restart_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

## 显示结束界面：win=true 胜利，false 失败。已经弹过就忽略（同时死亡时只弹一次）
static func show_result(win: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if tree.get_first_node_in_group("gameover") != null:
		return
	var scene: PackedScene = load("res://scenes/game_over.tscn")
	if scene == null:
		return
	var host := tree.current_scene
	if host == null:
		host = tree.root      # --script 之类没有 current_scene 的情况，挂到根窗口上
	var ui := scene.instantiate()
	host.add_child(ui)
	ui.setup(win)
