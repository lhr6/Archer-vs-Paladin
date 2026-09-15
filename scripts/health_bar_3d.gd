extends Node3D
## 头顶 3D 血条：背景深色底 + 前景绿色填充（可伸缩），始终面向相机
##
## 【血条会"跟着背景变"的三个坑，改这里之前务必先看】
##
## 1) 材质必须是**不透明**的（不要开 transparency）。
##    之前 Frame/Background/Fill 三层都是半透明面片，而半透明物体不是按节点顺序画的，
##    是 Godot 按"到相机的距离"整体排序后画的。当 Fill 缩小（血少）时，它的 AABB 中心
##    会往左移，于是它到相机的距离反而比 Background 更远 → Background 被判为"更近"，
##    结果深色底被画在绿色填充**之上**，整条血条看起来就是空的。血量越低越容易触发
##    （实测 ratio ≤ 0.4 完全看不见填充），而且排序依赖相机距离，所以表现成"和背景有关"。
##    现在三层全不透明 → 走不透明渲染 + 逐像素深度测试，谁离相机近谁盖谁，与背景无关。
##
## 2) 三层之间的 Z 间隔不能省（Frame 0 / Background 0.005 / Fill 0.01）。
##    Billboard 的 +Z 正好朝向相机，所以 Z 越大越靠前。有间隔才能让深度测试稳定分层。
##
## 3) 材质里**不能**开 billboard_mode。
##    Godot 的材质级 billboard 在着色器里会把模型矩阵的旋转和缩放一起丢掉（只保留平移），
##    那样 fill.scale.x 就不会作用到顶点上，只剩子节点的偏移被父级缩放影响，
##    结果就是填充条宽度不变、还整体跑出边框外。所以 billboard 由本脚本手动做。

@onready var billboard: Node3D = $Billboard
@onready var fill: Node3D = $Billboard/Fill

func _process(_delta: float) -> void:
	# 只取相机的朝向、保留自己的世界位置：既面向相机，又跟着角色移动
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	billboard.global_transform = Transform3D(cam.global_transform.basis, billboard.global_position)

func set_ratio(ratio: float) -> void:
	# 前景从右边收缩，左边缘固定在血条左端（Fill 节点就是左端枢轴）
	fill.scale.x = clampf(ratio, 0.0, 1.0)

func set_bar_visible(v: bool) -> void:
	visible = v
