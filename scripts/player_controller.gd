extends CharacterBody3D

# 移动参数
# 注意：速度需与动画步频匹配，否则会滑步
# RunForward 一个循环 3.148m / 0.9s ≈ 3.5 m/s，所以跑步速度取 3.5
@export var run_speed: float = 3.5
# 蓄力（拉弓）时的移动速度：动画步频 AimWalkForward 1.388m/1.233s ≈ 1.13 m/s，
# 取 1.15 与步频匹配；侧向步频更快（≈1.45），横移时按 1.25 倍加成防滑步
@export var aim_walk_speed: float = 1.15
@export var aim_strafe_scale: float = 1.25
# 近战
@export var melee_damage: float = 25.0   # 一拳伤害
@export var melee_range: float = 2.0     # 攻击距离（米）
@export var melee_angle: float = 100.0   # 攻击扇形角度（总角度，度）
# 踢击（F 键）：StandingMeleeKick，命中后敌人播 Impact2 并硬直 + 击退
@export var kick_damage: float = 15.0
@export var kick_range: float = 2.5
@export var kick_angle: float = 90.0
@export var rotation_speed: float = 10.0
@export var gravity: float = -9.8
@export var jump_speed: float = 5.0        # 起跳初速度，约可跳 1.3 米高
@export var dodge_speed: float = 3.5       # 翻滚位移速度（与翻滚动画 3.61m/1.67s 的原生速度匹配）
@export var roll_speed_scale: float = 1.6  # 翻滚动画播放速度（1.67s / 1.6 ≈ 1.04s 完成）
@export var air_control: float = 0.5       # 空中操控系数（0=完全不能空中转向）

# 真正的翻滚动画：Hips 累计旋转 414°（身体翻转一圈），StandingDodge* 其实是小跳
const ROLL_ANIM := "StandingDiveForward"
# 落地/起跳共用的下蹲动画：髋部 0.989 → 0.676（t=0.233s 最低） → 0.940
const LAND_ANIM := "FallALandToStandingIdle01"
const CROUCH_TIME := 0.23         # 该动画蹲到最低点的时刻
const LAND_LENGTH := 0.733        # 该动画总时长
const JUMP_CROUCH_SPEED := 1.2    # 蓄力下蹲的播放速度（0.23/1.2 ≈ 0.19 秒蹲到底）
# 蹬地伸展阶段：从蹲姿最低点站起（0.23 → 0.733），加速播完立刻切空中姿态。
# 不加速的话，整个上升期都在播"起身"，看上去就是蹲下动画在空中播放。
const JUMP_EXTEND_SPEED := 3.0    # （0.733-0.23）/3.0 ≈ 0.17 秒完成伸展
const LAND_ABSORB_TIME := 0.25    # 落地后下蹲吸震阶段（此期间锁住移动，蹲完才响应输入）
const LAND_BLEND_TIME := 0.15     # 落地被打断时与跑步动画的混合时长，避免姿势突变

# 蓄力瞄准相关动画
const AIM_WALK_ANIM := "StandingAimWalk"    # + Forward/Back/Left/Right 后缀
const AIM_HOLD_ANIM := "StandingAimOverdraw"  # 满弓保持（首尾姿态一致，可循环）
const AIM_DRAW_ANIM := "StandingDrawArrow"    # 拉弓一次性动作（1.03s），结束正好接满弓
const AIM_BLEND_TIME := 0.15

# 近战与受击
const MELEE_ANIM := "StandingMeleePunch"         # 左键近战（1.033s）
const MELEE_HIT_AT := 0.4                        # 前摇 40% 处判定伤害（挥拳命中的时机）
const KICK_ANIM := "StandingMeleeKick"           # F 键踢击
const KICK_HIT_AT := 0.5                         # 前摇 50% 处判定（脚踹出去的瞬间）
const HIT_REACT_ANIM := "StandingReactSmallFromFront"  # 我方受击（1.3s）
const STAGGER_TIME := 0.55                       # 受击硬直时长（动作继续播完，这段时间不能操作）

# 击飞（被回旋劈第二段命中）：死亡动画前 80 帧 + 抛物线 + 落地弹跳 + 起身回 IDLE
const KNOCK_DEATH_ANIM := "StandingDeathBackward01"  # 3.10s / 93 帧 / 30fps
const KNOCK_ANIM_FRAMES := 80                   # 击飞期间播放死亡动画的前 80 帧
const KNOCK_ANIM_FPS := 30.0
const KNOCK_BOUNCE := 0.4                       # 第一次落地弹跳的垂直速度比例
const KNOCK_DRAG := 3.0                         # 击飞水平阻尼（每秒减速量）

# 音效（3D 位置音，挂在玩家身上）
const SFX_SWORD := preload("res://assets/audio/sword_whoosh.ogg")
const SFX_SHOOT := preload("res://assets/audio/shoot.ogg")
const SFX_CHARGE := preload("res://assets/audio/charge.ogg")
const SFX_HIT := preload("res://assets/audio/hit_impact.ogg")
var _sfx: AudioStreamPlayer3D = null

func _play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = AudioStreamPlayer3D.new()
		add_child(_sfx)
	_sfx.stream = stream
	_sfx.volume_db = volume_db
	_sfx.pitch_scale = pitch
	_sfx.play()

# 组件引用
@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var skeleton: Skeleton3D = $Model/Armature/Skeleton3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera
# 注意：这个模型的转换工具把几何体和节点名弄乱了——
# 名叫 Eyes_Mesh 的节点里装的才是"箭"的几何体（贴图为箭纹理，位于脚下）。
# 名叫 Arrow_Mesh 的节点里装的是衣服/躯干，隐藏它会导致身体消失！
@onready var arrow_mesh: MeshInstance3D = $Model/Armature/Skeleton3D/Erika_Archer_Eyes_Mesh
@onready var health: Node = $Health

# 蓄力时脚下的漩涡特效
const ChargeVortexScript := preload("res://scripts/charge_vortex.gd")
var vortex  # ChargeVortex 实例（用 untyped 引用，避免新脚本未被项目索引时类型解析失败）

# 箭弹场景
const ArrowScene := preload("res://scenes/arrow_projectile.tscn")

# 结束界面（静态调用，避免引用实例）
const GameOverScript := preload("res://scripts/game_over.gd")

# 状态枚举
enum State { IDLE, RUN, AIM, SHOOT, DODGE }
var current_state: State = State.IDLE

# 翻滚 / 跳跃
var dodge_timer: float = 0.0
var dodge_dir: Vector3 = Vector3.ZERO
var is_dodging: bool = false
var is_airborne: bool = false
var is_landing: bool = false
var land_timer: float = 0.0      # 落地缓冲计时
var is_crouching_jump: bool = false  # 起跳前的下蹲蓄力中

# 近战 / 受击硬直
var is_attacking: bool = false
var is_staggered: bool = false
var stagger_timer: float = 0.0

# 射击相关
var is_charging: bool = false
var charge_time: float = 0.0
var max_charge_time: float = 1.5
var arrow_power: float = 1.0
var is_firing: bool = false   # 射击硬直中：普攻（后坐）动画播完前不能再次蓄力/发射

# 二倍速模式：SpeedMode 单例驱动（F 切换），动画/移动/重力/计时统一乘倍
var _base_scale: float = 1.0   # 当前动画基础播放速度（翻滚 1.6 / 起跳蓄力 1.2 / 蹬地 3.0 / 其余 1.0）

# 跳射混合：上半身专用 AnimationPlayer（只驱动 Spine 及后代）；主 AP 驱动下半身
var upper_ap: AnimationPlayer
var jump_air: bool = false      # 处于"空中下落/滞空"姿态（每帧由物理状态推导）
var using_hybrid: bool = false  # 是否处于"空中攻击"混合状态（主AP下半身 + upper_ap上半身）

# 相机俯仰角限制（弧度）：正值抬头，负值低头
const PITCH_MAX: float = 0.6   # 最多抬头约 34°
const PITCH_MIN: float = -1.2  # 最多低头约 69°
const ROOT_MOTION_THRESHOLD: float = 0.3  # 位置轨道位移超过该幅度即视为根位移，予以剥离
# 相机高度略高于角色头顶（约 1.75m），角色会落在画面中线偏下，
# 准星（屏幕中心）不再被自己的身体挡住，背后的敌人也更少被遮挡
const CAMERA_HEIGHT: float = 2.05
# 相机俯角：抬高相机后只需很小的下俯，主要靠高度把角色压到中线以下
const CAMERA_PITCH: float = -0.03
var camera_pitch: float = 0.0

# 鼠标锁定状态：true = 锁定在窗口中心（光标隐藏），false = 显示可自由移动
var mouse_locked: bool = true

# 死亡状态
var is_dead: bool = false

# 击飞状态（回旋劈第二段命中）：期间播死亡动画前 80 帧、做抛物线运动，落地弹跳后起身
var is_knocked: bool = false
var _knock_vel: Vector3 = Vector3.ZERO     # 击飞当前速度（水平 + 垂直）
var _knock_bounced: bool = false           # 是否已弹跳过
var _knock_anim_done: bool = false         # 死亡动画前 80 帧是否已播完（定格在倒地姿态）

func _ready() -> void:
	# 加入玩家组（供敌人AI/HUD查找），连接死亡信号
	add_to_group("player")
	health.died.connect(_on_died)
	health.took_damage.connect(_on_took_damage)

	# 默认锁定鼠标在窗口中心：CAPTURED 会把指针锁在窗口内，光标隐藏，
	# 不会像 HIDDEN 那样只是隐藏图标、指针仍可跑出屏幕
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# 隐藏箭，需要的时候再显示
	if arrow_mesh:
		arrow_mesh.visible = false

	# 同步相机初始俯仰角，并摆到角色背后（模型正面为 +Z，相机需在 -Z 侧）
	camera_pivot.rotation.y = PI
	camera.rotation.x = CAMERA_PITCH
	camera_pitch = camera.rotation.x

	# 相机脱离角色朝向：CameraPivot 原本是角色的子节点，角色一转向整个世界就跟着转
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position + Vector3(0, CAMERA_HEIGHT, 0)

	# 蓄力漩涡特效：挂在角色脚下（碰撞体底部即局部原点，所以直接作为子节点）
	vortex = ChargeVortexScript.new()
	vortex.name = "ChargeVortex"
	add_child(vortex)

	# 剥离动画自带的根位移（root motion），位移改由物理移动驱动
	_strip_root_motion()

	# 构建跳射混合（双 AnimationPlayer：主 AP 下半身 FallALoop + 上半身专用 AP 射击）
	_setup_hybrid()

	# 连接全局倍速（二倍速）开关：切换时重算所有速度与计时
	SpeedMode.factor_changed.connect(_on_speed_mode_changed)
	_set_base_scale(1.0)

	# 可循环播放的动画：待机/跑步/空中/落地 + 蓄力走/满弓保持
	for anim_name in ["StandingIdle01", "StandingRunForward", "StandingRunBack",
			"StandingRunLeft", "StandingRunRight", "FallALoop",
			"StandingAimWalkForward", "StandingAimWalkBack",
			"StandingAimWalkLeft", "StandingAimWalkRight", "StandingAimOverdraw"]:
		if animation_player.has_animation(anim_name):
			animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	
	# 打印所有可用动画（调试用）
	print("可用动画:")
	for anim in animation_player.get_animation_list():
		print("  - ", anim)
	
	# 播放默认待机动画
	play_animation("StandingIdle01")

func _notification(what: int) -> void:
	# 窗口失焦时 Godot 会自动释放鼠标捕获（否则你没法操作别的程序），
	# 重新获得焦点后要把锁定恢复回来，否则鼠标会处于可见且不受控状态
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN and mouse_locked:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 兜底：锁定状态下鼠标移出窗口（多显示器/边缘快速甩动），立即拉回中心
	if what == NOTIFICATION_WM_MOUSE_EXIT and mouse_locked:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var center := get_viewport().get_visible_rect().size / 2.0
			Input.warp_mouse(center)

func _physics_process(delta: float) -> void:
	# 死亡：停止移动逻辑，只保留重力与减速，动画由死亡动画接管
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, _run_speed() * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _run_speed() * 10.0 * delta)
		move_and_slide()
		return

	# 击飞：抛物线飞行 + 落地弹跳；死亡动画前 80 帧由协程播放并定格，起身条件满足后回 IDLE
	if is_knocked:
		_knock_vel.y += _gravity() * delta
		_knock_vel.x = move_toward(_knock_vel.x, 0.0, KNOCK_DRAG * _speed_mult() * delta)
		_knock_vel.z = move_toward(_knock_vel.z, 0.0, KNOCK_DRAG * _speed_mult() * delta)
		velocity = _knock_vel
		move_and_slide()
		# 第一次落地：弹跳一下；第二次落地：停住
		if is_on_floor() and _knock_vel.y < 0.0:
			if not _knock_bounced:
				_knock_bounced = true
				_knock_vel.y = -_knock_vel.y * KNOCK_BOUNCE
				_knock_vel.x *= 0.3
				_knock_vel.z *= 0.3
			else:
				_knock_vel.y = 0.0
		# 起身：死亡动画 80 帧播完 且 已落地弹跳并停住
		if _knock_anim_done and _knock_bounced and is_on_floor() and _knock_vel.y >= -0.01:
			_end_knockback()
			# 相机继续跟随
		camera_pivot.global_position = global_position + Vector3(0, CAMERA_HEIGHT, 0)
		return

	# 重力（二倍速下 ×4：跳跃高度不变、滞空时间减半）
	if not is_on_floor():
		velocity.y += _gravity() * delta

	# 获取输入（相机朝向为基准）
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir: Vector3 = (camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	if move_dir.length_squared() > 0.0:
		move_dir = move_dir.normalized()

	if is_staggered:
		# 受击硬直：完全不能动，动作播完后自动解除
		stagger_timer -= delta
		if stagger_timer <= 0.0:
			is_staggered = false
		velocity.x = move_toward(velocity.x, 0.0, _run_speed() * 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _run_speed() * 14.0 * delta)
	elif is_attacking:
		# 近战出拳中：只能小幅挪动（与蓄力同速），不能冲刺/翻滚/跳跃
		if input_dir != Vector2.ZERO:
			velocity.x = move_toward(velocity.x, move_dir.x * _aim_walk_speed(), _aim_walk_speed() * 12.0 * delta)
			velocity.z = move_toward(velocity.z, move_dir.z * _aim_walk_speed(), _aim_walk_speed() * 12.0 * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, _aim_walk_speed() * 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, _aim_walk_speed() * 12.0 * delta)
	elif is_dodging:
		# 翻滚：整段时间沿翻滚方向冲刺，不受输入影响
		dodge_timer -= delta
		velocity.x = dodge_dir.x * _dodge_speed()
		velocity.z = dodge_dir.z * _dodge_speed()
		if dodge_timer <= 0.0:
			end_dodge()
	elif is_landing:
		# 落地缓冲：下蹲吸震阶段锁住移动，否则会出现"双脚贴地半蹲滑行"。
		# 吸震结束后如果玩家按了方向键，就打断剩余起身动画、平滑过渡到跑步
		land_timer += delta
		velocity.x = move_toward(velocity.x, 0.0, _run_speed() * 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _run_speed() * 14.0 * delta)
		if land_timer >= LAND_ABSORB_TIME / _speed_mult() and input_dir != Vector2.ZERO:
			_break_landing(move_dir)
		elif land_timer >= LAND_LENGTH / _speed_mult():
			_end_landing()
	elif current_state == State.AIM:
		# 蓄力移动：大幅降速（约为跑步的 1/3），并播 StandingAimWalk* 而不是普通跑步
		if input_dir != Vector2.ZERO:
			var suffix := _direction_suffix(move_dir, "Back")
			var spd: float = _aim_walk_speed()
			if suffix == "Left" or suffix == "Right":
				spd *= aim_strafe_scale   # 侧向动画步频更快，提速以匹配、避免滑步
			velocity.x = move_toward(velocity.x, move_dir.x * spd, spd * 12.0 * delta)
			velocity.z = move_toward(velocity.z, move_dir.z * spd, spd * 12.0 * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, _aim_walk_speed() * 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, _aim_walk_speed() * 12.0 * delta)
	elif current_state == State.SHOOT:
		# 射击后坐硬直：站定
		velocity.x = move_toward(velocity.x, 0.0, _run_speed() * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _run_speed() * 10.0 * delta)
	else:
		# 常态移动：默认就是跑
		var control: float = 1.0 if is_on_floor() else air_control
		velocity.x = move_toward(velocity.x, move_dir.x * _run_speed(), _run_speed() * 12.0 * control * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * _run_speed(), _run_speed() * 12.0 * control * delta)

	# 移动
	move_and_slide()

	# 相机跟随角色位置，但不跟随角色朝向（避免角色转向时世界跟着旋转）
	camera_pivot.global_position = global_position + Vector3(0, CAMERA_HEIGHT, 0)

	if current_state == State.AIM:
		# 蓄力中：面向镜头正前方（准星方向），前后左右的移动才有明确参照
		var aim_fwd: Vector3 = -camera.global_transform.basis.z
		aim_fwd.y = 0.0
		if aim_fwd.length_squared() > 0.0001:
			rotation.y = lerp_angle(rotation.y, atan2(aim_fwd.x, aim_fwd.z), rotation_speed * delta)
	elif current_state == State.SHOOT:
		# 射击硬直：保持发射瞬间的朝向，不随输入转体（否则后坐动画未播完按 S 会背对目标）
		pass
	else:
		# 常态：角色面向移动方向（翻滚时面向翻滚方向；落地吸震中不转身，避免半蹲时扭身）
		var face_dir: Vector3 = dodge_dir if is_dodging else move_dir
		if face_dir != Vector3.ZERO and not is_landing:
			var target_rotation: float = atan2(face_dir.x, face_dir.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	# 落地检测：播放落地动画
	_check_landing(input_dir)

	# 更新动画状态
	update_animation_state(input_dir, move_dir)

	# 蓄力计时（同时驱动脚下漩涡的收窄与转速）：二倍速下蓄满时间减半
	if is_charging:
		charge_time += delta
		if charge_time >= _max_charge():
			charge_time = _max_charge()
		arrow_power = charge_time / _max_charge()
		if vortex:
			vortex.set_progress(arrow_power)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return

	# Alt 切换鼠标锁定/显示
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ALT:
				mouse_locked = not mouse_locked
				# 锁定用 CAPTURED（指针锁在窗口中心、光标隐藏），显示用 VISIBLE
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_locked else Input.MOUSE_MODE_VISIBLE
			KEY_SHIFT:
				try_dodge()
			KEY_SPACE:
				try_jump()
			KEY_F:
				try_kick()

	# 右键开始蓄力瞄准
	if event.is_action_pressed("aim"):
		start_aim()

	# 左键近战攻击
	if event.is_action_pressed("attack"):
		try_attack()
	
	# 右键松开，射击
	if event.is_action_released("aim"):
		release_aim()
	
	# 鼠标控制相机旋转：锁定模式（CAPTURED）下自由转动，否则按住右键拖动
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		camera_pivot.rotate_y(-event.relative.x * 0.005)
		# 用独立变量记录俯仰角，做严格限制，避免浮点累积越界
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.005, PITCH_MIN, PITCH_MAX)
		camera.rotation.x = camera_pitch

func start_aim() -> void:
	if is_dodging or is_attacking or is_staggered or is_crouching_jump or is_firing or is_knocked:
		return
	is_charging = true
	charge_time = 0.0
	current_state = State.AIM
	_play_sfx(SFX_CHARGE, -4.0, 1.0)   # 强化/蓄力起手

	# 脚下漩涡亮起
	if vortex:
		vortex.start()

	# 显示箭
	if arrow_mesh:
		arrow_mesh.visible = true
	
	# 播放拉弓动画（结束后会自动切到满弓保持 StandingAimOverdraw）
	# 空中时上半身由跳射混合的 upper_ap 负责；主 AP 不能播整段（全身动画会把腿带回站立）
	if not is_airborne:
		_set_base_scale(1.0)
		play_animation(AIM_DRAW_ANIM)

func release_aim() -> void:
	if not is_charging:
		return

	is_charging = false
	current_state = State.SHOOT
	is_firing = true   # 锁住：普攻（后坐）动画播完前不能再次蓄力/发射，避免疯狂点击无限重置

	# 漩涡淡出
	if vortex:
		vortex.stop()

	# 射击逻辑：发射箭
	shoot_arrow()
	_play_sfx(SFX_SHOOT, -2.0, 1.0)   # 射箭

	# 播放射击后坐动画，并等到它播完才解除锁定（下一次普攻必须等本次动画结束）
	# 空中时后坐由跳射混合的 upper_ap 负责；主 AP 若播整段会把腿带回站立
	if not is_airborne:
		_set_base_scale(1.0)
		play_animation("StandingAimRecoil")
	var rec_anim: Animation = animation_player.get_animation("StandingAimRecoil")
	var rec_len: float = rec_anim.length if rec_anim else 0.6
	await get_tree().create_timer(rec_len / _speed_mult()).timeout

	if arrow_mesh:
		arrow_mesh.visible = false
	is_firing = false
	current_state = State.IDLE
	# 空中时不要播站立待机（会打断跳射混合的下半身）；落地后自然由 update_animation_state 恢复
	if not is_airborne:
		play_animation("StandingIdle01")

func shoot_arrow() -> void:
	# 准星射线：从相机中心沿相机前方发出，找到准星在世界上命中的点
	var cam_forward: Vector3 = -camera.global_transform.basis.z
	var ray_from: Vector3 = camera.global_position
	var ray_to: Vector3 = ray_from + cam_forward * 200.0
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_areas = false
	query.exclude = [get_rid()]   # 不命中发射者自己
	var res := get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = ray_to if res.is_empty() else res.position

	# 从弓（胸前偏前）发射，方向指向"准星命中点"：
	# 这样箭的飞行轨迹与准星线重合 —— 你准星指哪，箭就命中哪，
	# 不再因为箭从胸口出生、比相机低约 0.7m 而"偏下命中"头顶上方的目标。
	var bow_pos: Vector3 = global_position + Vector3.UP * 1.35 + cam_forward * 0.6
	var dir: Vector3 = (aim_point - bow_pos).normalized()

	var arrow: Node3D = ArrowScene.instantiate()
	# 加到当前场景根（玩家所在世界），避免跟随玩家移动
	get_parent().add_child(arrow)
	arrow.global_position = bow_pos
	# 第三参数 = 蓄力进度：箭身放大/发光，满蓄力命中还能把敌人击飞
	arrow.setup(dir, 20.0 * arrow_power, arrow_power)
	print("射击！力量: ", arrow_power, " 伤害: ", 20.0 * arrow_power)
	if arrow_power >= FULL_CHARGE_POWER:
		_spawn_shot_flash(bow_pos, arrow_power)

## 蓄满判定（与 arrow_projectile 的 FULL_CHARGE_POWER 保持一致）：
## 只有蓄满的箭才有金色光效 + 击飞敌人
const FULL_CHARGE_POWER := 0.995

## 蓄满射击的出弓闪光：在弓的位置爆一下金色强光
func _spawn_shot_flash(pos: Vector3, power: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.32)   # 蓄满的金色
	light.light_energy = 6.0 + 6.0 * power
	light.omni_range = 2.6 + 2.5 * power
	add_child(light)
	light.global_position = pos
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.18)
	tween.tween_callback(light.queue_free)

func _on_died() -> void:
	is_dead = true
	jump_air = false
	if using_hybrid:
		_exit_hybrid()   # 死亡时若还在空中混合，先交还 AnimationPlayer，好播死亡动画
	remove_from_group("player")  # 敌人不再把尸体当目标
	# 停止蓄力与脚下特效
	if is_charging:
		is_charging = false
		if vortex:
			vortex.stop()
	if arrow_mesh:
		arrow_mesh.visible = false
	# 播放死亡动画（向后倒），不再响应任何输入
	_set_base_scale(1.0)
	play_animation("StandingDeathBackward01")
	_show_game_over()

## 玩家阵亡：等倒地动作演完（3.1s 的死亡动画，2.6s 时已经躺平）再弹 YOU DIE
const GAME_OVER_DELAY := 2.6
func _show_game_over() -> void:
	await get_tree().create_timer(GAME_OVER_DELAY / _speed_mult()).timeout
	if not is_dead:
		return
	GameOverScript.show_result(false)

func update_animation_state(input_dir: Vector2, move_dir: Vector3) -> void:
	# 跳射混合优先：只要“确实离地悬空”就启用混合树（下半身跳跃 / 上半身瞄准），
	# 与是否在蓄力/射击无关——这是 jump_air 的唯一权威来源。
	# 旧逻辑只在 try_jump 第三段、或 _check_landing 里（且排除 AIM/SHOOT 状态）才置位 jump_air，
	# 导致“空中右键瞄准/左键射击”时 jump_air 始终为 false、混合树不接管，于是整副骨架都在播
	# 站立射击（腿不弯）。改为每帧由物理状态推导，彻底修掉该问题。
	jump_air = is_airborne and not is_on_floor()
	if jump_air and not is_dead:
		_update_hybrid_anim()
		return
	if using_hybrid:
		_exit_hybrid()
		# 退出混合后不 return：让下方逻辑继续挑选落地/待机/跑步动画

	# 蓄力瞄准：走动播 StandingAimWalk*，站定保持满弓（拉弓动作播完前不打断）
	if current_state == State.AIM:
		var aim_anim := ""
		if input_dir != Vector2.ZERO:
			aim_anim = AIM_WALK_ANIM + _direction_suffix(move_dir, "Back")
		elif animation_player.current_animation == AIM_DRAW_ANIM \
				and animation_player.current_animation_position < animation_player.current_animation_length - 0.05:
			return  # 拉弓动作还没播完，别打断
		else:
			aim_anim = AIM_HOLD_ANIM
		if animation_player.current_animation != aim_anim:
			play_animation(aim_anim, AIM_BLEND_TIME)
		return

	# 射击、翻滚、近战、受击硬直、空中、落地中这些状态由各自逻辑负责动画，这里不打断
	if current_state == State.SHOOT or is_dodging or is_attacking or is_staggered \
			or is_airborne or is_landing:
		return

	var new_state: State = State.RUN if input_dir != Vector2.ZERO else State.IDLE

	if new_state == State.IDLE:
		if current_state != State.IDLE:
			current_state = State.IDLE
			play_animation("StandingIdle01")
	else:
		var anim := "StandingRun" + _direction_suffix(move_dir, "Back")
		if current_state != State.RUN or animation_player.current_animation != anim:
			current_state = State.RUN
			play_animation(anim)

# 左键近战：StandingMeleePunch（1.033s），前摇 40% 处判定伤害
func try_attack() -> void:
	if is_dead or is_dodging or is_attacking or is_staggered or is_crouching_jump or is_knocked:
		return
	if current_state == State.AIM or current_state == State.SHOOT:
		return   # 拉弓/射击中不挥拳
	if not is_on_floor():
		return

	is_attacking = true
	# 面向镜头正前方出拳，命中判定也以这个方向为准
	var aim_fwd: Vector3 = -camera.global_transform.basis.z
	aim_fwd.y = 0.0
	if aim_fwd.length_squared() > 0.0001:
		rotation.y = atan2(aim_fwd.x, aim_fwd.z)
	_set_base_scale(1.0)
	play_animation(MELEE_ANIM)
	_play_sfx(SFX_SWORD, -6.0, 1.0)

	var anim: Animation = animation_player.get_animation(MELEE_ANIM)
	var len: float = anim.length if anim else 1.033

	# 前摇结束：判定伤害（二倍速下判定同步提前）
	await get_tree().create_timer(len * MELEE_HIT_AT / _speed_mult()).timeout
	if is_dead:
		return
	if is_attacking and not is_staggered:
		_melee_hit()

	# 动作播完：解除出拳状态
	await get_tree().create_timer(len * (1.0 - MELEE_HIT_AT) / _speed_mult()).timeout
	is_attacking = false

# 近战命中判定：镜头正前方扇形范围内、射程内的敌人
func _melee_hit() -> void:
	var fwd: Vector3 = -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var cos_limit: float = cos(deg_to_rad(melee_angle * 0.5))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == null or not is_instance_valid(e):
			continue
		if e.get("is_dead"):
			continue
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		var d: float = to_e.length()
		if d > melee_range or d < 0.0001:
			continue
		if to_e.normalized().dot(fwd) < cos_limit:
			continue
		var hp: Node = e.get_node_or_null("Health")
		if hp:
			hp.take_damage(melee_damage, &"melee")

# F 键踢击：StandingMeleeKick，命中瞬间敌人播 Impact2 并硬直 + 击退
func try_kick() -> void:
	if is_dead or is_dodging or is_attacking or is_staggered or is_crouching_jump or is_knocked:
		return
	if current_state == State.AIM or current_state == State.SHOOT:
		return
	if not is_on_floor():
		return

	is_attacking = true
	var aim_fwd: Vector3 = -camera.global_transform.basis.z
	aim_fwd.y = 0.0
	if aim_fwd.length_squared() > 0.0001:
		rotation.y = atan2(aim_fwd.x, aim_fwd.z)
	_set_base_scale(1.0)
	play_animation(KICK_ANIM)
	_play_sfx(SFX_SWORD, -6.0, 1.15)   # 踢：略高一点的 whoosh

	var anim: Animation = animation_player.get_animation(KICK_ANIM)
	var len: float = anim.length if anim else 0.8

	await get_tree().create_timer(len * KICK_HIT_AT / _speed_mult()).timeout
	if is_dead:
		return
	if is_attacking and not is_staggered:
		_kick_hit()

	await get_tree().create_timer(len * (1.0 - KICK_HIT_AT) / _speed_mult()).timeout
	is_attacking = false

# 踢中判定：镜头正前方扇形内的敌人 → 扣血 + 触发击退硬直
func _kick_hit() -> void:
	var fwd: Vector3 = -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var cos_limit: float = cos(deg_to_rad(kick_angle * 0.5))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == null or not is_instance_valid(e):
			continue
		if e.get("is_dead"):
			continue
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		var d: float = to_e.length()
		if d > kick_range or d < 0.0001:
			continue
		if to_e.normalized().dot(fwd) < cos_limit:
			continue
		var hp: Node = e.get_node_or_null("Health")
		if hp:
			hp.take_damage(kick_damage, &"kick")
		# 击退硬直：敌人自己按"背离玩家"方向滑出去
		if e.has_method("start_kick_stun"):
			e.start_kick_stun(global_position)

# 受击：硬直 + 受击动作，并打断正在进行的动作（蓄力/翻滚/出拳）
func _on_took_damage(_amount: float, _kind: StringName) -> void:
	if is_dead:
		return
	if is_knocked:
		return   # 击飞（倒地）期间不再受击/打断，避免倒地时被鞭尸
	# 打断蓄力
	if is_charging:
		is_charging = false
		if vortex:
			vortex.stop()
		if arrow_mesh:
			arrow_mesh.visible = false
	# 打断翻滚
	if is_dodging:
		is_dodging = false
		dodge_timer = 0.0
	_set_base_scale(1.0)
	is_attacking = false
	current_state = State.IDLE
	is_staggered = true
	stagger_timer = STAGGER_TIME / _speed_mult()
	play_animation(HIT_REACT_ANIM)
	_play_sfx(SFX_HIT, -4.0, 1.0)

# 被技能击飞：抛物线 + 死亡动画前 80 帧 + 落地弹跳 + 起身回 IDLE。
# from_pos 为攻击者位置（击飞方向＝背离攻击者），hspd/vspd 为水平/垂直初速（米每秒）。
func start_knockback(from_pos: Vector3, hspd: float, vspd: float) -> void:
	if is_dead or is_knocked:
		return
	# 打断当前所有动作（含受击硬直：第二段伤害先触发普通受击，随即被击飞覆盖）
	is_charging = false
	is_dodging = false
	is_attacking = false
	is_crouching_jump = false
	is_landing = false
	is_airborne = false
	is_staggered = false
	stagger_timer = 0.0
	dodge_timer = 0.0
	if vortex:
		vortex.stop()
	if arrow_mesh:
		arrow_mesh.visible = false
	is_knocked = true
	_knock_bounced = false
	_knock_anim_done = false
	current_state = State.IDLE

	# 击飞方向：背离攻击者的水平方向
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -global_transform.basis.z
	away = away.normalized()
	# 初速：水平 + 向上；倍速下速度 ×2、重力 ×4 → 抛物线高度不变、滞空减半（与跳跃一致）
	_knock_vel = away * (hspd * _speed_mult()) + Vector3.UP * (vspd * _speed_mult())

	# 播放死亡动画前 80 帧：播到该处暂停（定格倒地姿态），起身时再切站立
	_set_base_scale(1.0)
	play_animation(KNOCK_DEATH_ANIM)
	_play_knock_anim()

func _play_knock_anim() -> void:
	await get_tree().create_timer(KNOCK_ANIM_FRAMES / KNOCK_ANIM_FPS / _speed_mult()).timeout
	if is_knocked and not is_dead:
		animation_player.pause()   # 定格在死亡动画第 80 帧（倒地姿态）
		# physics_frame 信号在物理帧开始时恢复协程（早于节点 _physics_process）：
		# 等两帧，第一帧让"定格状态"可被观察到，第二帧才放行起身，避免同帧定格+起身被吞掉
		await get_tree().physics_frame
		await get_tree().physics_frame
		if is_knocked and not is_dead:
			_knock_anim_done = true

# 击飞结束：起身（落地起身动画），复用落地吸震机制——吸震锁移动、播完回待机，
# 期间按方向键可提前起身跑动
func _end_knockback() -> void:
	is_knocked = false
	_knock_bounced = false
	_knock_anim_done = false
	current_state = State.IDLE
	_set_base_scale(1.0)
	is_landing = true
	land_timer = 0.0
	play_animation(LAND_ANIM)

func try_dodge() -> void:
	# 翻滚（Shift）：地面、非瞄准、非翻滚、非出拳、非硬直、非起跳蓄力中、非击飞才能触发
	if is_dodging or is_airborne or is_crouching_jump or is_attacking or is_staggered \
			or current_state == State.AIM or current_state == State.SHOOT or is_knocked:
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir == Vector2.ZERO:
		dodge_dir = global_transform.basis.z  # 没按方向键就朝正前方翻滚（模型正面为 +Z）
	else:
		dodge_dir = (camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	is_dodging = true
	current_state = State.DODGE
	# 用 DiveForward 播放翻滚，加速播放；持续时间 = 动画时长 / 播放速度（二倍速下再减半）
	var anim: Animation = animation_player.get_animation(ROLL_ANIM)
	dodge_timer = anim.length / (roll_speed_scale * _speed_mult())
	play_animation(ROLL_ANIM)
	_set_base_scale(roll_speed_scale)
	# 立刻面向翻滚方向
	rotation.y = atan2(dodge_dir.x, dodge_dir.z)

func end_dodge() -> void:
	is_dodging = false
	dodge_timer = 0.0
	_set_base_scale(1.0)
	current_state = State.IDLE
	play_animation("StandingIdle01")

func try_jump() -> void:
	# 跳跃（空格）：地面才能起跳，翻滚/蓄力/出拳/硬直/击飞中不能跳
	if not is_on_floor() or is_dodging or is_crouching_jump or is_attacking or is_staggered \
			or current_state == State.AIM or is_knocked:
		return

	# 第一段：蓄力下蹲（站立 → 蹲到最低点），期间角色不产生任何垂直位移
	is_crouching_jump = true
	current_state = State.IDLE
	_set_base_scale(JUMP_CROUCH_SPEED)
	play_animation(LAND_ANIM)
	await get_tree().create_timer(CROUCH_TIME / (JUMP_CROUCH_SPEED * _speed_mult())).timeout
	is_crouching_jump = false
	if not is_on_floor() or is_dodging:  # 蓄力期间状态被打断，放弃起跳
		_set_base_scale(1.0)
		return

	# 第二段：蹬地起跳。速度在这一刻才生效，动画随之进入伸展（蹲姿 → 站起）
	# 二倍速下起跳速度 ×2、重力 ×4 → 高度不变、滞空减半
	velocity.y = jump_speed * _speed_mult()
	is_airborne = true
	_set_base_scale(JUMP_EXTEND_SPEED)
	await get_tree().create_timer((LAND_LENGTH - CROUCH_TIME) / (JUMP_EXTEND_SPEED * _speed_mult())).timeout

	# 第三段：伸展结束后进入空中姿态（FallALoop 是标准空中姿势，髋部恒为 0.99）
	if is_airborne and not is_on_floor():
		_set_base_scale(1.0)
		jump_air = true   # 进入空中姿态：启用跳射混合树
		play_animation("FallALoop")

func _check_landing(input_dir: Vector2) -> void:
	# 掉落（走下坡/悬崖）时也进入空中状态
	if not is_on_floor() and not is_airborne and not is_dodging \
			and velocity.y < -2.0 and current_state != State.AIM:
		is_airborne = true
		jump_air = true   # 离地即启用跳射混合树

	# 空中且正在下落：才切换到蜷缩下落动画（上升阶段保持原动画，避免半空下蹲）
	if is_airborne and not is_on_floor() and velocity.y < 0.0 \
			and animation_player.current_animation != "FallALoop" \
			and current_state != State.AIM and current_state != State.SHOOT:
		jump_air = true
		play_animation("FallALoop")

	# 只有在下落阶段（velocity.y <= 0）触地才算落地，避免起跳当帧就误判落地
	if is_airborne and is_on_floor() and velocity.y <= 0.0:
		is_airborne = false
		jump_air = false   # 落地：关闭混合树，交还 AnimationPlayer
		is_landing = true
		# 落地动画：还在跑就用带位移的落地，站定就用落地到待机
		# 注意必须把播放速度还原：起跳伸展阶段会临时加速，否则落地会一闪而过
		_set_base_scale(1.0)
		var anim := "FallALandToRunForward" if input_dir != Vector2.ZERO else "FallALandToStandingIdle01"
		play_animation(anim)
		land_timer = 0.0
		# 后续由 _physics_process 的 is_landing 分支接管：
		# 吸震阶段锁住移动，之后若有输入就打断并平滑切到跑步

# 落地吸震结束后玩家按了方向键：打断剩余起身动画，混合过渡到跑步
func _break_landing(move_dir: Vector3) -> void:
	is_landing = false
	land_timer = 0.0
	current_state = State.RUN
	play_animation("StandingRun" + _direction_suffix(move_dir, "Back"), LAND_BLEND_TIME)

# 落地动画自然播完：回到待机
func _end_landing() -> void:
	is_landing = false
	land_timer = 0.0
	current_state = State.IDLE
	play_animation("StandingIdle01", LAND_BLEND_TIME)

# 根据移动方向相对角色朝向，返回动画后缀（Forward / Back / Left / Right）
# 注意：这个模型的正面是 +Z（glTF 惯例），不是 Godot 常规的 -Z
func _direction_suffix(dir: Vector3, back_name: String) -> String:
	if dir == Vector3.ZERO:
		return "Forward"
	var fwd: Vector3 = global_transform.basis.z
	var right: Vector3 = -global_transform.basis.x
	var angle: float = rad_to_deg(atan2(dir.dot(right), dir.dot(fwd)))
	if absf(angle) < 60.0:
		return "Forward"
	if absf(angle) > 120.0:
		return back_name
	return "Right" if angle > 0.0 else "Left"

func play_animation(anim_name: String, blend: float = -1.0) -> void:
	# 安全播放动画，如果动画不存在就跳过。blend >= 0 时与当前姿势混合过渡
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name, blend)
	else:
		print("动画不存在: ", anim_name)

# ----------------------------------------------------------------------------
# 全局倍速（二倍速）：SpeedMode 单例按 F 切换，factor=1.0 正常 / 2.0 二倍速。
# 动画、移动速度、跳跃、重力、计时全部统一乘倍，保证"跑速↔步频"不滑步、
# 跳跃高度不变但滞空减半、判定与动画时长同步缩短。
# ----------------------------------------------------------------------------

func _speed_mult() -> float:
	return SpeedMode.factor

func _run_speed() -> float:
	return run_speed * _speed_mult()

func _aim_walk_speed() -> float:
	return aim_walk_speed * _speed_mult()

func _dodge_speed() -> float:
	return dodge_speed * _speed_mult()

# 2x 世界下的重力：加速度 ×4、起跳速度 ×2 → 跳跃高度不变、滞空时间减半
func _gravity() -> float:
	return gravity * _speed_mult() * _speed_mult()

func _max_charge() -> float:
	return max_charge_time / _speed_mult()

# 设置动画基础播放速度，实际播放速度 = 基础 × 全局倍速
func _set_base_scale(base: float) -> void:
	_base_scale = base
	animation_player.speed_scale = base * _speed_mult()

func _on_speed_mode_changed(_factor: float) -> void:
	# 切换倍速时按当前基础速度重新应用（动画位置不变，只是播速改变）
	_set_base_scale(_base_scale)

# ----------------------------------------------------------------------------
# 跳射混合：空中攻击时，下半身播跳跃（FallALoop），上半身叠瞄准/射击动画，
# 比"空中直接播站立瞄准射击"自然。
# 实现：**两个 AnimationPlayer**。主 AP 只播"下半身裁剪版 FallALoop"（仅髋+腿轨道），
# 另建一个上半身 AP 只播"上半身裁剪版 射击动画"（仅 Spine 及后代轨道）。
# 两者轨道互不相交，合成天然正确，不依赖 AnimationTree 的骨骼过滤
# （实测该过滤在本模型上不生效：会导致整副骨架跟随单一动画 → 腿绷直）。
# 非攻击的纯跳跃：退出混合，主 AP 照常播完整 FallALoop。
# ----------------------------------------------------------------------------

const HYB_LOWER_ANIM := "__hyb_fall_lower"
const HYB_UP_PREFIX := "__hyb_up_"
const HYB_UPPER_CLIPS := ["StandingDrawArrow", "StandingAimOverdraw", "StandingAimRecoil"]

func _setup_hybrid() -> void:
	if animation_player == null or skeleton == null:
		return
	# 主 AP：加一个只含下半身轨道的 FallALoop
	_add_reduced_clip(animation_player, HYB_LOWER_ANIM, "FallALoop", _lower_body_bones())
	# 上半身专用 AP：放在主 AP 同父节点下，保证轨道路径解析一致
	if upper_ap == null:
		upper_ap = AnimationPlayer.new()
		upper_ap.name = "UpperBodyAP"
		animation_player.get_parent().add_child(upper_ap)
	var up_set := _upper_body_bones()
	for clip in HYB_UPPER_CLIPS:
		_add_reduced_clip(upper_ap, HYB_UP_PREFIX + clip, clip, up_set)

# 复制 src 动画，只保留 keep 集合内的骨骼轨道，加入 target_ap 的动画库
func _add_reduced_clip(target_ap: AnimationPlayer, new_name: String, src_name: String, keep: Dictionary) -> void:
	var src: Animation = animation_player.get_animation(src_name)
	if src == null:
		return
	var a: Animation = src.duplicate(true)
	var rm: Array = []
	for i in a.get_track_count():
		var p := str(a.track_get_path(i))
		var bone := p.get_slice(":", 1) if p.contains(":") else p
		if not keep.has(bone):
			rm.append(i)
	rm.reverse()   # 从后往前删，避免索引错位
	for i in rm:
		a.remove_track(i)
	# 取（或创建）目标 AP 的默认动画库。空库列表时不要调用 get_animation_library("")（会报错）
	var lib: AnimationLibrary = null
	var libs: PackedStringArray = target_ap.get_animation_library_list()
	if libs.size() > 0:
		lib = target_ap.get_animation_library(libs[0])
	if lib == null:
		lib = AnimationLibrary.new()
		target_ap.add_animation_library("", lib)
	lib.add_animation(new_name, a)

# 上半身骨骼名集合：Spine 及其所有后代（胸/颈/头/双臂/手指）
func _upper_body_bones() -> Dictionary:
	var d := {}
	if skeleton == null:
		return d
	var stack := [skeleton.find_bone("mixamorig_Spine")]
	while stack.size() > 0:
		var idx: int = stack.pop_back()
		if idx >= 0:
			d[String(skeleton.get_bone_name(idx))] = true
			for c in skeleton.get_bone_children(idx):
				stack.append(c)
	return d

# 下半身骨骼名集合：Hips 及其后代，去掉 Spine 子树（即髋+双腿+双脚）
func _lower_body_bones() -> Dictionary:
	var d := {}
	if skeleton == null:
		return d
	var stack := [skeleton.find_bone("mixamorig_Hips")]
	while stack.size() > 0:
		var idx: int = stack.pop_back()
		if idx >= 0:
			d[String(skeleton.get_bone_name(idx))] = true
			for c in skeleton.get_bone_children(idx):
				stack.append(c)
	for n in _upper_body_bones().keys():
		d.erase(n)
	return d

# 每帧（空中时）由 update_animation_state 调用
func _update_hybrid_anim() -> void:
	var attacking: bool = is_charging or current_state == State.SHOOT or is_firing
	if not attacking:
		# 纯跳跃（未攻击）：不混合，主 AP 照常播完整 FallALoop
		if using_hybrid:
			_exit_hybrid()
		if animation_player.current_animation != "FallALoop":
			animation_player.play("FallALoop")
		return
	# 空中攻击：主 AP 只驱动下半身，上半身交给 upper_ap
	using_hybrid = true
	# 上半身专用 AP 跟随全局倍速
	if upper_ap:
		upper_ap.speed_scale = _speed_mult()
	# 关键：主 AP 必须始终停在"下半身裁剪版 FallALoop"上。
	# start_aim()/release_aim() 会用 play_animation 在 main AP 上播整段【全身】站立动画
	# （StandingDrawArrow / StandingAimRecoil / StandingIdle01），那会把下半身也带回站立姿势，
	# 表现为"发射瞬间腿变直"。这里每帧把它拉回下半身裁剪版，保证腿始终是 FallALoop。
	if animation_player.current_animation != HYB_LOWER_ANIM:
		animation_player.play(HYB_LOWER_ANIM)
	var up: String = HYB_UP_PREFIX + _hybrid_upper_clip()
	if upper_ap != null and upper_ap.current_animation != up:
		upper_ap.play(up)

func _hybrid_upper_clip() -> String:
	if is_charging:
		# 拉弓约 1s（二倍速下 0.5s），之后保持满弓；与地面的 StandingDrawArrow→StandingAimOverdraw 一致
		return "StandingAimOverdraw" if charge_time >= 1.0 / _speed_mult() else "StandingDrawArrow"
	if current_state == State.SHOOT or is_firing:
		return "StandingAimRecoil"
	return "StandingDrawArrow"

func _exit_hybrid() -> void:
	if upper_ap != null and upper_ap.is_playing():
		upper_ap.stop()   # 停掉上半身覆盖，交还主 AP 播完整动画
	using_hybrid = false

func _strip_root_motion() -> void:
	# Mixamo 动画把位移烘在了 Root 骨骼的位置轨道上：循环播放时 Root 每圈弹回原点，
	# 表现为"地板在转 / 人物滑步"。这里把该位置轨道整条移除，让动画变成原地版，
	# 位移完全交给 CharacterBody 的物理移动驱动。Hips 轨道只是上下起伏，保留。
	# 注意：Godot 导入时会把 "mixamorig:Root" 规范成 "mixamorig_Root"（冒号变下划线），
	# 所以这里同时用名字匹配 + 位移幅度判断，避免匹配失效。
	var lib := animation_player.get_animation_library("")
	if lib == null:
		push_warning("找不到动画库，无法剥离根位移")
		return

	for anim_name in lib.get_animation_list():
		var anim := lib.get_animation(anim_name).duplicate() as Animation
		var changed := false
		for i in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
				continue
			var path := String(anim.track_get_path(i))
			# 只处理 Root 骨骼：名字里含 Root，或位移幅度明显过大（超过 0.3 米）。
			# 注意：绝不能动 Hips！翻滚（Hips Y 0.94→0.17）和落地（0.99→0.68）
			# 正是靠髋部下沉才贴地，删掉就会"浮空翻滚/浮空下蹲"。
			if path.contains("Hips"):
				continue
			if path.contains("Root") or _track_displacement(anim, i) > ROOT_MOTION_THRESHOLD:
				anim.remove_track(i)
				changed = true
		if changed:
			lib.remove_animation(anim_name)
			lib.add_animation(anim_name, anim)

# 计算一条位置轨道的整体位移幅度（各轴最大跨度）
func _track_displacement(anim: Animation, track: int) -> float:
	var key_count: int = anim.track_get_key_count(track)
	if key_count == 0:
		return 0.0
	var min_v: Vector3 = anim.track_get_key_value(track, 0)
	var max_v: Vector3 = min_v
	for k in range(1, key_count):
		var v: Vector3 = anim.track_get_key_value(track, k)
		min_v = min_v.min(v)
		max_v = max_v.max(v)
	var d: Vector3 = max_v - min_v
	return max(d.x, max(d.y, d.z))
