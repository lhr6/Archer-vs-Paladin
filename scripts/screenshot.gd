extends Node3D
# 临时截图脚本：运行后在第 N 帧从不同角度截图，然后自动退出
var frame := 0
var camera: Camera3D

func _ready() -> void:
	camera = $World/Player/CameraPivot/Camera
	# 拉高分辨率窗口，截图更清晰
	get_window().size = Vector2i(1600, 900)

func _process(_delta: float) -> void:
	frame += 1
	match frame:
		60:
			# 视角1：默认跟随视角（角色背影 + 前方草地 + 天空）
			camera.rotation.x = -0.12
			_snap("01_default_view.png")
		90:
			# 视角2：平视，重点看地平线/天空与地面的交界
			camera.rotation.x = -0.02
			_snap("02_horizon.png")
		120:
			# 视角3：俯视，看地面纹理细节与重复度
			camera.rotation.x = -0.45
			_snap("03_ground_detail.png")
		150:
			# 视角4：转个方向看侧面/接缝
			camera.rotation.x = -0.06
			$World/Player/CameraPivot.rotate_y(-1.2)
			_snap("04_side_view.png")
		180:
			print("截图完成，退出")
			get_tree().quit()

func _snap(filename: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := "C:/project/act/_screenshots/"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + filename)
	print("已保存: ", filename)
