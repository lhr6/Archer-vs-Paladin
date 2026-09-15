extends Node3D
## 箭弹：沿发射方向直线飞行（射线检测防穿透），命中后插在目标上并跟随目标移动。
## 命中敌人 → 挂到敌人节点下（跟着敌人走）并扣血；命中地面/墙 → 钉在原地。
## 蓄力箭（power > 0）：飞行途中箭身放大、自发光 + 外层光晕 + 点光源 + 拖尾；
## **插到目标上的瞬间就恢复成普通箭**（光效只属于"射出去的那一下"）。
## 蓄满（power ≈ 1）额外出金色强光效，并且只有蓄满的箭才能把敌人击飞。

const MAX_LIFE := 4.0            # 飞行最长存活时间（秒）
const STUCK_LIFE := 10.0         # 命中后停留时间（秒）
const EMBED_DEPTH := 0.12        # 箭尖埋入目标的深度
# 箭模型的几何实测值：箭尖到节点原点 0.445m（箭长 0.75m，节点原点不在正中）
const TIP_OFFSET := 0.445

@export var speed: float = 42.0
@export var damage: float = 20.0

## 蓄力箭外观
@export var charge_color: Color = Color(1.0, 0.72, 0.25)  # 蓄力光效颜色（暖金）
@export var full_charge_color: Color = Color(1.0, 0.86, 0.32)  # 蓄满时的金色（更亮更饱和）
@export var charge_max_scale: float = 1.9                   # 满蓄力时箭身放大倍数
@export var charge_speed_bonus: float = 1.35                # 满蓄力时飞行速度倍数
@export var glow_min_power: float = 0.15                    # 低于该蓄力进度不做光效（普通快射）
## 击飞：只有"蓄满"的箭才能把敌人击飞（蓄满时才有金色光效）
@export var knock_horizontal: float = 7.0  # 击飞水平初速（米每秒）
@export var knock_vertical: float = 6.0    # 击飞垂直初速（米每秒）

# 蓄满判定：arrow_power = charge_time / max_charge，按住足够久会被 clamp 到 1.0，
# 留一点浮点余量，避免差一帧就判不满
const FULL_CHARGE_POWER := 0.995

var direction: Vector3 = Vector3.FORWARD
var life_time: float = 0.0
var power: float = 0.0     # 蓄力进度 0~1（0 = 普通速射）
var _stuck := false
var _scale := 1.0
var _light: OmniLight3D = null
var _trail: GPUParticles3D = null
# 命中后要把外观还原成普通箭，这些是"加特效"时动过的东西的记录
var _tinted: Array[MeshInstance3D] = []
var _orig_mats: Array[Material] = []
var _halos: Array[MeshInstance3D] = []

func is_full_charge() -> bool:
	return power >= FULL_CHARGE_POWER

@onready var model: Node3D = $Model

func _ready() -> void:
	add_to_group("arrow")

# 初始化发射方向、伤害与蓄力进度，并对齐箭身朝向
# 注意：模型子节点已在场景里绕 Y 转 180°，所以箭尖正好指向 direction
func setup(dir: Vector3, dmg: float, p: float = 0.0) -> void:
	direction = dir.normalized()
	damage = dmg
	power = clampf(p, 0.0, 1.0)
	if absf(direction.dot(Vector3.UP)) < 0.999:
		look_at(global_position + direction, Vector3.UP)
	else:
		# 几乎垂直发射时换一个参考向量，避免 look_at 报错
		look_at(global_position + direction, Vector3.RIGHT)
	if power >= glow_min_power:
		speed *= lerpf(1.0, charge_speed_bonus, power)
		_apply_charge_visuals()

func _physics_process(delta: float) -> void:
	if _stuck:
		return

	var step: Vector3 = direction * speed * delta

	# 本帧位移内做射线检测（比碰撞体更稳，不会因速度快而穿透目标）
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	query.collide_with_areas = false
	var player := get_tree().get_first_node_in_group("player")
	if player and player is CollisionObject3D:
		query.exclude = [player.get_rid()]  # 不命中发射者自己
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if not result.is_empty():
		_stick(result.collider, result.position)
		return

	global_position += step
	life_time += delta
	if life_time >= MAX_LIFE:
		queue_free()

# 命中：把箭扎在目标上（挂到目标节点下，随目标一起移动）
func _stick(target: Node, hit_pos: Vector3) -> void:
	_stuck = true
	set_physics_process(false)
	remove_from_group("arrow")
	if _trail != null:
		_trail.emitting = false

	# 让箭尖埋入命中点 EMBED_DEPTH，其余箭身留在外面（放大后的箭要按放大后的箭尖算）
	global_position = hit_pos - direction * (TIP_OFFSET * _scale - EMBED_DEPTH)

	if target != null:
		# 挂到被命中物体下：敌人身上会跟着它跑，地面则钉在原地
		reparent(target, true)
		if target.is_in_group("enemy"):
			# 先击飞再结算伤害：这样即使这一箭致命，也会先飞出去再倒地，
			# 而不是原地直接播死亡动画。只有蓄满的箭才有击飞效果
			if is_full_charge() and target.has_method("start_knockback"):
				target.start_knockback(global_position, knock_horizontal, knock_vertical)
			var hp: Node = target.get_node_or_null("Health")
			if hp:
				hp.take_damage(damage, &"ranged")

	# 插上就变回普通箭：光效只属于"射出去的那一下"
	_clear_charge_visuals()

	# 停留一段时间后回收
	await get_tree().create_timer(STUCK_LIFE).timeout
	if is_instance_valid(self):
		queue_free()

## 蓄力箭外观（只在飞行期间存在）：放大 + 自发光 + 外层光晕 + 点光源 + 拖尾粒子。
## 蓄满时额外提一档：更亮更饱和的金色 + 更粗的光晕 + 更密的拖尾。
func _apply_charge_visuals() -> void:
	var full: bool = is_full_charge()
	var col: Color = full_charge_color if full else charge_color
	_scale = lerpf(1.0, charge_max_scale, power)
	if model != null:
		model.scale = Vector3.ONE * _scale

	# 1) 箭身自发光：复制原材质后开 emission，保留原有贴图（记录原材质，命中后好还原）
	for mi in _collect_meshes(model if model != null else self):
		var orig := mi.get_surface_override_material(0)   # 可能为 null（用网格自带材质）
		var base := mi.get_active_material(0)
		if base != null:
			var dup := base.duplicate()
			if dup is StandardMaterial3D:
				dup.emission_enabled = true
				dup.emission = col
				# 满蓄力只加一档亮度：加色混合下能量太高会过曝成白色，看不出"金色"
				dup.emission_energy_multiplier = 1.0 + 2.6 * power + (1.0 if full else 0.0)
			mi.set_surface_override_material(0, dup)
			_tinted.append(mi)
			_orig_mats.append(orig)
		# 2) 外层光晕：同网格放大一圈，加色混合（无 bloom 后处理也能看出在发光）
		if mi.mesh != null:
			var halo := MeshInstance3D.new()
			halo.mesh = mi.mesh
			halo.transform = mi.transform
			halo.scale = mi.scale * (1.35 if full else 1.22)
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			halo.material_override = _halo_material(col, full)
			mi.add_child(halo)
			_halos.append(halo)

	# 3) 点光源：照亮周围，飞行时看得见光晕
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 0.8 + 2.6 * power + (2.0 if full else 0.0)
	_light.omni_range = 1.6 + 1.2 * power + (0.8 if full else 0.0)
	add_child(_light)

	# 4) 拖尾：世界坐标发射，箭飞过去后粒子留在原地慢慢淡出
	_trail = _make_trail(col, full)
	add_child(_trail)

## 命中后：把飞行期间加的特效全部撤掉，恢复成一支普通箭
func _clear_charge_visuals() -> void:
	if _scale <= 1.001:
		return
	# 箭身缩回原尺寸后，原来按"放大后的箭尖"对齐的位置要重新对齐（否则箭会往外窜一截）
	global_position += direction * TIP_OFFSET * (_scale - 1.0)
	_scale = 1.0
	if model != null:
		model.scale = Vector3.ONE
	for i in _tinted.size():
		_tinted[i].set_surface_override_material(0, _orig_mats[i])
	_tinted.clear()
	_orig_mats.clear()
	for h in _halos:
		if is_instance_valid(h):
			h.queue_free()
	_halos.clear()
	if _light != null:
		_light.queue_free()
		_light = null
	if _trail != null:
		_trail.emitting = false   # 停发即可，残留粒子会自己淡出（世界坐标不受箭影响）
		_trail = null

func _halo_material(col: Color, full: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.35 + 0.4 * power + (0.2 if full else 0.0))
	return m

func _make_trail(col: Color, full: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 56 if full else 28     # 蓄满：拖尾更密
	p.lifetime = 0.38 if full else 0.32
	p.local_coords = false      # 世界坐标：粒子留在发射处，形成拖尾
	p.emitting = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 45.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5 if full else 0.4
	pm.scale_max = 1.1 if full else 0.85
	pm.color = col
	# 颜色随时间淡出（加色混合下＝慢慢消失）
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_texture = _soft_dot_texture()   # 圆形软边，否则方块会露出硬边
	qm.albedo_color = Color(1, 1, 1, 1)
	qm.vertex_color_use_as_albedo = true      # 让粒子颜色/透明度生效
	quad.material = qm
	p.draw_pass_1 = quad
	return p

## 程序生成的圆形软边贴图（中心实、边缘透明），避免粒子显示为硬边方块
func _soft_dot_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_collect_meshes(c))
	return out
