extends Control
## 屏幕中央圆形准星：圆环 + 中心点

func _ready() -> void:
	# 不拦截鼠标事件，避免影响瞄准/射击输入
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var center := size / 2.0
	# 外圈圆环
	draw_arc(center, 13.0, 0.0, TAU, 40, Color(1, 1, 1, 0.95), 2.0)
	# 中心点
	draw_circle(center, 2.2, Color(1, 1, 1, 0.95))
