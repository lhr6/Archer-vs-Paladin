extends CharacterBody3D
## 敌人 NPC：平面无遮挡地图上的简单追踪 AI
## 状态：待机(远处) → 追踪(跑步) → 攻击(近战/回旋劈技能) → 死亡

enum State { IDLE, CHASE, ATTACK, SKILL, STAGGER, DEAD, INTRO, LAUNCHED }

## 可调参数
@export var move_speed: float = 3.2       # 追踪速度
@export var attack_range: float = 2.2     # 进入该距离开始攻击
@export var attack_hysteresis: float = 0.6 # 迟滞：进入攻击距离后，要退到 range+该值 才重新追击。
										   # 没有它时敌人会在攻击距离边缘逐帧横跳追击/待机（表现为"抽搐"）
@export var attack_cooldown: float = 2.2  # 两次攻击间隔
@export var damage: float = 12.0          # 每次攻击伤害
@export var aggro_range: float = 30.0     # 玩家进入该距离才开始追踪
@export var gravity: float = -9.8         # 重力加速度

## 回旋劈技能参数（SwordAndShieldSlash4，二段伤害）
@export var skill_cooldown: float = 5.0   # 技能冷却时间（秒）：冷却就绪且玩家距离在 [skill_distance, skill_max_distance] 内才释放
@export var skill_distance: float = 8.0   # 突进位移距离（米），同时是释放条件：玩家距离大于该值才放
@export var skill_max_distance: float = 14.0  # 距离上限：太远（如刚开局隔着半个地图）不放技能，先跑过去
@export var skill_range: float = 3.5      # 第二段（劈地开裂）伤害半径（米）＝开裂视觉效果半径
@export var skill_angle: float = 90.0     # 第二段伤害扇形角度（前方，总角度）＝开裂视觉角度
@export var skill_hit_frame_start: int = 30  # 第一段伤害窗口起始帧（动画 30fps）；突进也在此帧前完成
@export var skill_hit_frame_end: int = 40    # 第一段伤害窗口结束帧；此帧劈地触发第二段
## 第一段（下劈）：范围很小，基本要正好站在剑前才受伤
@export var skill_first_range: float = 2.2    # 第一段判定半径（米）：突进 8m 到位后玩家约 1.8m，够得着但仍远小于第二段
@export var skill_first_angle: float = 40.0   # 第一段扇形角度（总角度，很窄）
@export var skill_first_damage: float = 10.0  # 第一段伤害
@export var skill_second_damage: float = 18.0 # 第二段伤害
@export var skill_crack_dist: float = 1.2     # 劈地点在敌人前方的距离（米）
## 击飞：第二段命中后玩家被击飞（水平初速 / 垂直初速，米每秒）
@export var skill_knockback_speed: float = 5.5
@export var skill_knockback_up: float = 5.5

## 被蓄力箭击飞（抛物线）参数
@export var knock_drag: float = 3.0        # 击飞水平阻尼（每秒减速量）
@export var knock_bounce: float = 0.4      # 第一次落地弹跳的垂直速度比例
@export var down_time: float = 1.2         # 落地后倒地不起的时长（秒），到点后起身继续战斗
@export var getup_speed: float = 1.6       # 起身速度（把死亡动画倒放，躺平 → 站立）

## 被玩家踢中（F 键）：Impact2 第 16 帧定格 + 沿背离玩家方向击退
@export var kick_knockback_dist: float = 2.0   # 【击退米数调这里】
@export var kick_freeze_frame: int = 16        # 播到第几帧硬注定格（30fps）
@export var kick_stun_hold: float = 0.3        # 定格后保持硬直姿态的额外秒数

## 尸体贴地：死亡动画里髋部高度恒定 0.954m，身体绕髋转平后整个人会悬空约 0.8m。
## 这里按"身体竖直程度"把模型压回地面——站立时不动，躺平后髋部落到 corpse_hips_y。
@export var corpse_hips_y: float = 0.13        # 完全躺平时髋部离地高度（米）
@export var corpse_settle_speed: float = 2.5    # 下沉/回升速度上限（米每秒），只影响过渡快慢

# Paladin 动画名（从模型实际读取）
const IDLE_ANIM := "SwordAndShieldIdle"
const RUN_ANIM := "SwordAndShieldRun"
const ATTACK_ANIM := "SwordAndShieldAttack2"
const DEATH_ANIM := "SwordAndShieldDeath"
# 回旋劈技能：垂直地面的旋转劈砍，实测 70 帧 / 30fps / 2.33s
const SKILL_ANIM := "SwordAndShieldSlash4"
const SKILL_ANIM_FPS := 30.0
# 受击动作：按伤害来源区分（近战/远程）
const HIT_MELEE_ANIM := "SwordAndShieldImpact2"    # 1.0s，被近战打中
const HIT_RANGED_ANIM := "SwordAndShieldImpact3"   # 0.733s，被箭射中
const STAGGER_SCALE := 0.7                         # 硬直时长 = 受击动画时长 × 该系数
# 开局预备动作（拔剑/收剑，0.867s）：战斗开始的起手，播放期间不追不打不放技能，
# 免得一进场就隔着老远一个回旋劈冲脸
const SHEATH_ANIM := "SheathSword2"
# 死亡动画定格时刻（秒）：2.05s 时身体已经完全躺平，击飞途中就定格在这个姿态
const DEATH_FREEZE_T := 2.05
# 躯干竖直度参考值（Spine2 骨骼自身 Y 轴的 Y 分量）：站立 ≈0.96、躺平 ≈0.12。
# 实际值不会精确到 0/1，用这两个参考值把它重映射到 0~1，站立时才不会误下沉。
const UPRIGHT_REF := 0.96
const LYING_REF := 0.12
const CORPSE_LIFE := 4.0    # 尸体停留时间（秒），倍速下同步减半
# 结束后等倒地动作演完再弹结算界面（死亡动画 2.33s，1.9s 时身体已躺平）
const RESULT_DELAY := 1.9

# 音效（3D 位置音，挂在敌人身上）
const SFX_SWORD := preload("res://assets/audio/sword_whoosh.ogg")
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

# 结束界面（静态调用，避免引用实例）
const GameOverScript := preload("res://scripts/game_over.gd")

var state: State = State.IDLE
var attack_timer: float = 0.0
var skill_timer: float = 0.0   # 技能冷却计时
var is_dead: bool = false
var is_staggered: bool = false      # 受击硬直：不能移动、不能攻击
var stagger_timer: float = 0.0
var _in_attack_range: bool = false  # 带迟滞的"在攻击距离内"判定

var _player: Node3D = null

# 回旋劈技能状态：突进方向（水平）、位移速度、突进完成时刻（动画时间秒，= 30 帧）
var _skill_dir: Vector3 = Vector3.FORWARD
var _skill_speed: float = 0.0
var _skill_dash_end: float = 1.0

# 开局预备动作
var _intro_active: bool = false

# 被蓄力箭击飞状态
var is_knocked: bool = false        # 抛物线飞行 / 倒地中（未起身前都为 true）
var _knock_vel: Vector3 = Vector3.ZERO
var _knock_bounced: bool = false    # 是否已经弹跳过一次
var _knock_anim_done: bool = false  # 死亡动画是否已播到"躺平"并定格
var _down_timer: float = 0.0        # 落地后倒地计时
var _getting_up: bool = false       # 起身上演中（倒放死亡动画），期间仍算 is_knocked

# 被踢击退：平移方向/速度、是否正在滑
var _kick_dir: Vector3 = Vector3.ZERO
var _kick_speed: float = 0.0
var _kick_sliding: bool = false

# 尸体（躺地）状态
var _corpse_life: float = 0.0       # 尸体剩余停留时间
var _shape_timer: float = 0.0       # 躺平后关闭碰撞体的倒计时
var _hips_idx: int = -1
var _spine_idx: int = -1
var _stand_hips_y: float = -1.0     # 站立时髋部高度（模型空间），首次贴地计算时捕获

@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var health: Node = $Health
@onready var health_bar: Node3D = $HealthBar3D
@onready var model: Node3D = $Model
@onready var skeleton: Skeleton3D = $Model/Armature/Skeleton3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("enemy")
	# 循环动画标记为循环
	for anim_name in [IDLE_ANIM, RUN_ANIM]:
		if animation_player.has_animation(anim_name):
			animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	# 连接血量信号
	health.health_changed.connect(_on_health_changed)
	health.took_damage.connect(_on_took_damage)
	health.died.connect(_on_died)
	# 连接全局倍速：敌人动画/移动/计时跟随 F 键切换的二倍速
	SpeedMode.factor_changed.connect(_on_speed_mode_changed)

	# 技能冷却从"满冷却"开始：否则 skill_timer 初值 0，一开局就满足释放条件直接旋风劈冲脸
	skill_timer = skill_cooldown

	# 尸体下沉需要的骨骼索引（站立髋高在首次贴地计算时按实测捕获）
	if skeleton != null:
		_hips_idx = skeleton.find_bone("mixamorig_Hips")
		_spine_idx = skeleton.find_bone("mixamorig_Spine2")

	# 开局预备动作：先播拔剑/收剑，播完才进入正常 AI
	_start_intro()

func _physics_process(delta: float) -> void:
	# 击飞中（蓄力箭命中）：抛物线飞行 + 落地弹跳 + 倒地，死亡与否都在这一段处理
	if is_knocked:
		_update_launched(delta)
		return

	# 死亡：不再行动，只做尸体贴地下沉并等待移除
	if is_dead:
		_update_corpse(delta)
		return

	# 开局预备动作：站着做完起手，期间不追、不打、不放技能
	if _intro_active:
		_update_intro(delta)
		return

	# 重力（二倍速下 ×4，与玩家一致）
	if not is_on_floor():
		velocity.y += _grav() * delta

	# 受击硬直：站定挨打，期间不追不打（攻击协程会因 state 变化自行中止）
	if is_staggered:
		stagger_timer -= delta
		if _kick_sliding:
			# 被踢击退：沿 _kick_dir 匀速滑出（16 帧内滑完击退距离）
			velocity.x = _kick_dir.x * _kick_speed
			velocity.z = _kick_dir.z * _kick_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, _spd() * 10.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, _spd() * 10.0 * delta)
		if stagger_timer <= 0.0:
			is_staggered = false
			state = State.CHASE
			play_animation(RUN_ANIM)
		move_and_slide()
		return

	# 回旋劈技能中：突进在挥砍（30 帧）前完成——动画时间未到 _skill_dash_end 前冲刺，
	# 之后快速刹停站定挥砍（不再平移），由协程负责伤害与收尾
	if state == State.SKILL:
		if animation_player.current_animation_position < _skill_dash_end:
			velocity.x = _skill_dir.x * _skill_speed
			velocity.z = _skill_dir.z * _skill_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, _spd() * 25.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, _spd() * 25.0 * delta)
		move_and_slide()
		return

	# 获取玩家（每次取最新，玩家可能重生/替换）
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		velocity.x = move_toward(velocity.x, 0.0, _spd() * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _spd() * 10.0 * delta)
		if state != State.IDLE:
			state = State.IDLE
			play_animation(IDLE_ANIM)
		move_and_slide()
		return

	attack_timer = maxf(0.0, attack_timer - delta)
	skill_timer = maxf(0.0, skill_timer - delta)

	# 计算朝向玩家的方向和距离（忽略高度差）
	var to_player: Vector3 = _player.global_position - global_position
	var flat: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	var dist: float = flat.length()
	var dir: Vector3 = flat.normalized() if dist > 0.001 else Vector3.ZERO

	# 始终面向玩家（平滑转身）
	if dir != Vector3.ZERO:
		var target_yaw: float = atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 8.0 * delta)

	# 超出警戒范围：待机，不追
	if dist > aggro_range:
		velocity.x = move_toward(velocity.x, 0.0, _spd() * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _spd() * 10.0 * delta)
		if state != State.IDLE:
			state = State.IDLE
			play_animation(IDLE_ANIM)
		move_and_slide()
		return

	# 迟滞判定：进攻击距离立刻生效，退出要等到 range + hysteresis，
	# 避免玩家在边界附近移动时敌人逐帧在追击/待机之间横跳
	if dist <= attack_range:
		_in_attack_range = true
	elif dist > attack_range + attack_hysteresis:
		_in_attack_range = false

	match state:
		State.ATTACK:
			# 攻击中站定，播完由 start_attack 的协程收尾
			velocity.x = move_toward(velocity.x, 0.0, _spd() * 10.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, _spd() * 10.0 * delta)
		_:
			if _in_attack_range:
				# 在攻击距离内：停步，冷却好了就攻击，否则待机
				velocity.x = move_toward(velocity.x, 0.0, _spd() * 10.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, _spd() * 10.0 * delta)
				if attack_timer <= 0.0:
					start_attack()
				elif state != State.IDLE:
					state = State.IDLE
					play_animation(IDLE_ANIM)
			else:
				# 追上去；技能冷却就绪且玩家距离在 (skill_distance, skill_max_distance] 内 →
				# 释放回旋劈突进拉近距离。加上距离上限，避免隔着半个地图也冲过来放技能
				if skill_timer <= 0.0 and dist > skill_distance and dist <= skill_max_distance:
					start_skill()
					move_and_slide()
					return
				velocity.x = dir.x * _spd()
				velocity.z = dir.z * _spd()
				if state != State.CHASE or animation_player.current_animation != RUN_ANIM:
					state = State.CHASE
					play_animation(RUN_ANIM)

	move_and_slide()

func start_attack() -> void:
	state = State.ATTACK
	attack_timer = attack_cooldown / _speed_mult()
	play_animation(ATTACK_ANIM)
	_play_sfx(SFX_SWORD, -6.0, 1.0)
	var anim: Animation = animation_player.get_animation(ATTACK_ANIM)

	# 前摇 40% 后造成伤害（挥击命中的时机，二倍速下同步提前）
	await get_tree().create_timer(anim.length * 0.4 / _speed_mult()).timeout
	if state != State.ATTACK or is_dead:
		return
	_try_hit_player()

	# 动画播完：还在攻击距离内就站着等冷却，否则才继续追。
	# （原来无条件切追击，会在下一帧被拉回待机，导致跑步动作只播一帧的抖动）
	await get_tree().create_timer(anim.length * 0.6 / _speed_mult()).timeout
	if state == State.ATTACK and not is_dead:
		if _in_attack_range:
			state = State.IDLE
			play_animation(IDLE_ANIM)
		else:
			state = State.CHASE
			play_animation(RUN_ANIM)

# 回旋劈技能：SwordAndShieldSlash4（70帧/30fps/2.33s），垂直地面的旋转劈砍，二段伤害。
# 突进在挥砍前完成：动画 0 → 30 帧（1.0s）内冲刺 skill_distance 米到位，30 帧后站定。
# 第一段（30~40 帧）：下劈过程，判定范围很小（贴脸窄扇形），命中一次即止；
# 第二段（40 帧）：劈到地上，地面开裂效果展开（视觉范围＝伤害范围，较大扇形），
# 命中后玩家被击飞（抛物线 + 死亡动画前 80 帧 + 落地弹跳 + 起身）。
func start_skill() -> void:
	state = State.SKILL
	skill_timer = skill_cooldown
	# 技能方向：朝向玩家的水平方向，起手瞬间锁定（突进中不跟随玩家转向）
	var to_player := Vector3.ZERO
	if _player:
		var flat := _player.global_position - global_position
		flat.y = 0.0
		to_player = flat.normalized()
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	_skill_dir = to_player if to_player.length_squared() > 0.001 else fwd.normalized()
	rotation.y = atan2(_skill_dir.x, _skill_dir.z)

	var anim: Animation = animation_player.get_animation(SKILL_ANIM)
	var len: float = anim.length if anim else 2.33
	# 突进速度：skill_distance 在 30 帧（突进完成时刻）内冲完；真实时长再除以倍速
	_skill_dash_end = float(skill_hit_frame_start) / SKILL_ANIM_FPS
	_skill_speed = skill_distance * _speed_mult() / _skill_dash_end
	play_animation(SKILL_ANIM)
	_play_sfx(SFX_SWORD, -4.0, 0.9)   # 回旋劈挥剑声

	# 第一段（下劈）：30~40 帧（30fps → 1.0s ~ 1.333s 动画时间；真实时间再除以倍速）
	# 窗口必须完整走完：命中一次后停止判定，但位移与动画继续播完，保证总时长 = 动画时长
	var hit_start: float = float(skill_hit_frame_start) / SKILL_ANIM_FPS
	var hit_end: float = float(skill_hit_frame_end) / SKILL_ANIM_FPS
	await get_tree().create_timer(hit_start / _speed_mult()).timeout
	if state != State.SKILL or is_dead:
		return
	var window_left := (hit_end - hit_start) / _speed_mult()
	var first_done := false
	while window_left > 0.0:
		if state != State.SKILL or is_dead:
			return
		if not first_done and _try_skill_hit_first():
			first_done = true   # 第一段窗口内命中一次即可
		window_left -= get_process_delta_time()
		await get_tree().process_frame

	# 第二段（40 帧劈地）：地面开裂效果展开（视觉范围＝伤害判定范围），大范围扇形伤害并击飞
	if state != State.SKILL or is_dead:
		return
	_spawn_ground_crack()
	_try_skill_hit_second()

	# 动画播完收尾（与普通攻击一致）
	await get_tree().create_timer((len - hit_end) / _speed_mult()).timeout
	if state == State.SKILL and not is_dead:
		if _in_attack_range:
			state = State.IDLE
			play_animation(IDLE_ANIM)
		else:
			state = State.CHASE
			play_animation(RUN_ANIM)

# 第一段（下劈）伤害判定：极窄的近距离扇形——基本要正好站在剑劈落处才受伤
func _try_skill_hit_first() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.get("is_dead"):
		return false
	var to_p: Vector3 = _player.global_position - global_position
	to_p.y = 0.0
	var d: float = to_p.length()
	if d > skill_first_range or d < 0.0001:
		return false
	if to_p.normalized().dot(_skill_dir) < cos(deg_to_rad(skill_first_angle * 0.5)):
		return false
	var hp_node: Node = _player.get_node_or_null("Health")
	if hp_node:
		hp_node.take_damage(skill_first_damage, &"melee")
		return true
	return false

# 第二段（劈地开裂）伤害判定：大范围扇形（与开裂视觉效果同参数），命中后击飞玩家
func _try_skill_hit_second() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.get("is_dead"):
		return
	var to_p: Vector3 = _player.global_position - global_position
	to_p.y = 0.0
	var d: float = to_p.length()
	if d > skill_range or d < 0.0001:
		return
	if to_p.normalized().dot(_skill_dir) < cos(deg_to_rad(skill_angle * 0.5)):
		return
	var hp_node: Node = _player.get_node_or_null("Health")
	if hp_node:
		hp_node.take_damage(skill_second_damage, &"melee")
		# 击飞：玩家按技能方向反方向做抛物线击飞
		if _player.has_method("start_knockback"):
			_player.start_knockback(global_position, skill_knockback_speed, skill_knockback_up)

# 地面开裂效果：在劈地点生成与第二段伤害范围一致的扇形开裂（视觉＝判定范围），
# 半透明开裂区域 + 从劈点向外辐射的裂缝，短暂停留后淡出。
func _spawn_ground_crack() -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	var root := Node3D.new()
	root.name = "GroundCrack"
	root.rotation.y = atan2(_skill_dir.x, _skill_dir.z)

	# 开裂扇形区域（半透明）：范围与第二段伤害判定一致
	var fan := _make_crack_mesh(_fan_mesh(skill_range, skill_angle), Color(0.22, 0.15, 0.08, 0.4))
	fan.position = Vector3(0, 0, skill_crack_dist)
	root.add_child(fan)
	# 从劈点向外辐射的裂缝折线
	var crack := _make_crack_mesh(_crack_mesh(skill_range), Color(0.09, 0.06, 0.03, 0.95))
	crack.position = Vector3(0, 0, skill_crack_dist)
	root.add_child(crack)

	world.add_child(root)
	root.global_position = global_position + Vector3(0, 0.02, 0)  # 入树后再定位，略高于地面避免闪烁

	# 淡出后移除（倍速下同步缩短停留时间）
	var fade_dur: float = 1.6 / _speed_mult()
	var tween := root.create_tween()
	var mats: Array[StandardMaterial3D] = []
	for child in root.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			mats.append(child.material_override)
	var base_colors: Array[Color] = []
	for m in mats:
		base_colors.append(m.albedo_color)
	for i in mats.size():
		var m: StandardMaterial3D = mats[i]
		var base: Color = base_colors[i]
		tween.parallel().tween_method(
			func(a: float) -> void: m.albedo_color = Color(base.r, base.g, base.b, base.a * (1.0 - a)),
			0.0, 1.0, fade_dur)
	tween.tween_callback(root.queue_free)

# 扇形网格（局部 XZ 平面，+Z 为技能前方中心线，圆心在原点）
func _fan_mesh(radius: float, angle_deg: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	var half := deg_to_rad(angle_deg) * 0.5
	var steps := 28
	for i in steps + 1:
		var a := -half + (2.0 * half) * float(i) / float(steps)
		verts.append(Vector3(sin(a) * radius, 0.0, cos(a) * radius))
		normals.append(Vector3.UP)
	for i in steps:
		idx.append(0); idx.append(i + 1); idx.append(i + 2)
	return _build_array_mesh(verts, normals, idx)

# 裂缝网格：从原点（劈点）出发的 7 条之字形裂缝，扩展成有宽度的带，末端收窄
func _crack_mesh(length: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec()) & 0xFFFF
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for c in 7:
		var pts: Array[Vector3] = [Vector3.ZERO]
		var angle := rng.randf_range(-1.0, 1.0) * deg_to_rad(skill_angle) * 0.5 * 0.8
		var cur := Vector3.ZERO
		var segs := 3 + rng.randi_range(0, 2)
		for s in segs:
			angle += rng.randf_range(-0.55, 0.55)
			var seg_len: float = rng.randf_range(0.35, 0.6) * length / skill_range
			cur += Vector3(sin(angle), 0.0, cos(angle)) * seg_len
			pts.append(cur)
		var w: float = 0.07 + rng.randf_range(0.0, 0.06)
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var seg: Vector3 = b - a
			if seg.length() < 0.001:
				continue
			var n := Vector3(-seg.z, 0.0, seg.x).normalized()
			var t: float = float(i) / float(maxi(pts.size() - 2, 1))
			var half_w: float = w * 0.5 * (1.0 - 0.65 * t)
			var a0 := a + n * half_w
			var a1 := a - n * half_w
			var b0 := b + n * half_w
			var b1 := b - n * half_w
			var vi := verts.size()
			verts.append(a0); verts.append(a1); verts.append(b0); verts.append(b1)
			normals.append(Vector3.UP); normals.append(Vector3.UP)
			normals.append(Vector3.UP); normals.append(Vector3.UP)
			idx.append(vi); idx.append(vi + 1); idx.append(vi + 2)
			idx.append(vi + 2); idx.append(vi + 1); idx.append(vi + 3)
	return _build_array_mesh(verts, normals, idx)

func _build_array_mesh(verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# 创建地面开裂的 MeshInstance3D（平铺在地面，略高于地面避免与地面闪烁）
func _make_crack_mesh(mesh: ArrayMesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _try_hit_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var d: float = global_position.distance_to(_player.global_position)
	if d <= attack_range + 0.6:
		var hp_node: Node = _player.get_node_or_null("Health")
		if hp_node:
			hp_node.take_damage(damage, &"melee")

# 受击：按来源播不同受击动作并进入硬直（打断当前攻击）
func _on_took_damage(_amount: float, kind: StringName) -> void:
	if is_dead:
		return
	if is_knocked:
		return   # 击飞/倒地期间不再触发受击硬直，免得打断抛物线
	if kind == &"kick":
		return   # 踢击的动画/16帧定格/击退由 start_kick_stun 全权处理
	_intro_active = false   # 起手被打断：直接进入战斗
	var anim_name := HIT_RANGED_ANIM if kind == &"ranged" else HIT_MELEE_ANIM
	var anim: Animation = animation_player.get_animation(anim_name)
	var len: float = anim.length if anim else 1.0
	state = State.STAGGER     # 改变状态即可让进行中的攻击协程中止
	is_staggered = true
	stagger_timer = len * STAGGER_SCALE / _speed_mult()
	play_animation(anim_name)
	_play_sfx(SFX_HIT, -4.0, 1.0)

# 被玩家踢中：播 Impact2，第 kick_freeze_frame 帧硬注定格，同时沿背离玩家方向击退。
# from_pos = 玩家位置（击退方向＝敌人到玩家的反方向）。
func start_kick_stun(from_pos: Vector3) -> void:
	if is_dead or is_knocked:
		return
	_intro_active = false
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -global_transform.basis.z
	away = away.normalized()

	state = State.STAGGER
	is_staggered = true
	# 硬直时长由本函数协程控制（stagger_timer 设大，物理分支不提前恢复）
	stagger_timer = 999.0
	play_animation(HIT_MELEE_ANIM)
	_play_sfx(SFX_HIT, -3.0, 0.9)

	# 第 16 帧时刻（秒）：这之前沿击退方向匀速滑完 kick_knockback_dist
	var freeze_dur: float = kick_freeze_frame / 30.0 / _speed_mult()
	_kick_dir = away
	_kick_speed = kick_knockback_dist / maxf(freeze_dur, 0.001)
	_kick_sliding = true

	await get_tree().create_timer(freeze_dur).timeout
	if is_dead:
		return
	# 滑完，定格在第 16 帧
	_kick_sliding = false
	velocity.x = 0.0
	velocity.z = 0.0
	animation_player.pause()

	await get_tree().create_timer(kick_stun_hold / _speed_mult()).timeout
	if is_dead:
		return
	if state == State.STAGGER and is_staggered:
		is_staggered = false
		state = State.CHASE
		play_animation(RUN_ANIM)

func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.set_ratio(current / maximum)

func _on_died() -> void:
	is_dead = true
	state = State.DEAD
	health_bar.visible = false
	# 必须在 is_knocked 判断之前发起：被蓄力箭击飞致死时下面会提前 return，
	# 漏掉这一步就永远弹不出结算界面
	_check_battle_end()
	if is_knocked:
		# 击飞途中被打死：保持飞行姿态与速度，落地后（_update_launched）才开始尸体计时
		return
	velocity = Vector3.ZERO
	_begin_corpse_timers()
	play_animation(DEATH_ANIM)

## 敌人阵亡后：等倒地演完，若场上再没有活着的敌人 → 弹 YOU WIN
func _check_battle_end() -> void:
	await get_tree().create_timer(RESULT_DELAY / _speed_mult()).timeout
	if not is_dead:
		return
	# 被击飞致死：身体还在空中／倒地未起身，等落地演完再结算（最多再等 4 秒）
	var guard := 0.0
	while is_knocked and guard < 4.0:
		await get_tree().physics_frame
		guard += get_process_delta_time()
	if not is_dead:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == null or not is_instance_valid(e):
			continue
		if not e.get("is_dead"):
			return
	GameOverScript.show_result(true)

## 尸体计时：躺平后多久关闭碰撞体、多久移除（从"身体落地"那一刻开始算）
func _begin_corpse_timers() -> void:
	_corpse_life = CORPSE_LIFE / _speed_mult()
	_shape_timer = (DEATH_FREEZE_T + 0.3) / _speed_mult()

## 尸体：贴地下沉 + 躺平后关掉站立胶囊 + 到点移除
func _update_corpse(delta: float) -> void:
	# 若死在半空（掉下平台、被打飞后没落到地面等）：先落回地面再躺平
	if collision_shape != null and not collision_shape.disabled and not is_on_floor():
		velocity.y += _grav() * delta
		velocity.x = move_toward(velocity.x, 0.0, _speed_mult() * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _speed_mult() * 6.0 * delta)
		move_and_slide()
	_settle_corpse(delta)
	if _shape_timer > 0.0:
		_shape_timer -= delta
		if _shape_timer <= 0.0 and collision_shape != null:
			# 胶囊还是"站着"的，尸体却已经躺平——留着会让箭打到空气、玩家被隐形墙挡住
			collision_shape.disabled = true
	_corpse_life -= delta
	if _corpse_life <= 0.0:
		queue_free()

## 把悬空的尸体压回地面：死亡/击飞动画里髋部高度恒定（≈0.95m），身体绕髋转平后
## 整个人会悬在半空。按"躯干竖直程度"插值出髋部应有的高度，再整体下移模型补上差值。
## 站立时竖直度≈1 → 不偏移；躺平时≈0 → 下沉到 corpse_hips_y。
func _settle_corpse(delta: float) -> void:
	if skeleton == null or _hips_idx < 0 or _spine_idx < 0:
		return
	var hips_y: float = skeleton.get_bone_global_pose(_hips_idx).origin.y
	var raw_up: float = skeleton.get_bone_global_pose(_spine_idx).basis.y.y
	var upness: float = clampf((raw_up - LYING_REF) / (UPRIGHT_REF - LYING_REF), 0.0, 1.0)
	if _stand_hips_y < 0.0:
		# 首次：以"还站着"时的髋高为基准（跑步/待机时髋部会略低一点，用实测值更准）
		_stand_hips_y = hips_y if upness > 0.85 else skeleton.get_bone_global_rest(_hips_idx).origin.y
	var want: float = corpse_hips_y + (_stand_hips_y - corpse_hips_y) * upness
	var diff: float = want - (hips_y + model.position.y)
	if absf(diff) < 0.002:
		return
	var step: float = clampf(diff, -corpse_settle_speed * delta, corpse_settle_speed * delta)
	model.position.y += step

## 被蓄力箭击飞：抛物线 + 死亡动画（躺平定格）+ 落地弹跳 + 起身
func start_knockback(from_pos: Vector3, hspd: float, vspd: float) -> void:
	if is_dead or is_knocked:
		return
	is_knocked = true
	state = State.LAUNCHED
	is_staggered = false
	_intro_active = false
	_down_timer = 0.0
	_knock_bounced = false
	_knock_anim_done = false
	_getting_up = false
	attack_timer = maxf(attack_timer, attack_cooldown * 0.5)

	# 击飞方向：背离箭来的方向（水平）
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -global_transform.basis.z
		away.y = 0.0
	away = away.normalized()
	rotation.y = atan2(-away.x, -away.z)   # 面朝攻击者倒下
	# 倍速下速度 ×2、重力 ×4 → 抛物线高度不变、滞空减半（与玩家跳跃一致）
	_knock_vel = away * (hspd * _speed_mult()) + Vector3.UP * (vspd * _speed_mult())
	play_animation(DEATH_ANIM)
	_play_knock_anim()

func _play_knock_anim() -> void:
	var anim: Animation = animation_player.get_animation(DEATH_ANIM)
	var freeze: float = minf(DEATH_FREEZE_T, anim.length if anim else DEATH_FREEZE_T)
	await get_tree().create_timer(freeze / _speed_mult()).timeout
	if not is_knocked:
		return
	animation_player.pause()   # 定格在"躺平"姿态
	_knock_anim_done = true

func _update_launched(delta: float) -> void:
	if _getting_up:
		# 起身上演中：站定不动，继续把模型从"贴地"抬回正常高度（否则会陷在地里跑）
		velocity = Vector3.ZERO
		move_and_slide()
		_settle_corpse(delta)
		return

	_knock_vel.y += _grav() * delta
	_knock_vel.x = move_toward(_knock_vel.x, 0.0, knock_drag * _speed_mult() * delta)
	_knock_vel.z = move_toward(_knock_vel.z, 0.0, knock_drag * _speed_mult() * delta)
	velocity = _knock_vel
	move_and_slide()
	if is_on_floor() and _knock_vel.y < 0.0:
		if not _knock_bounced:
			_knock_bounced = true
			_knock_vel.y = -_knock_vel.y * knock_bounce
			_knock_vel.x *= 0.3
			_knock_vel.z *= 0.3
		else:
			_knock_vel.y = 0.0

	# 身体一边翻倒一边压回地面（死亡动画髋部不下沉，全靠这里补）
	_settle_corpse(delta)

	var landed: bool = _knock_anim_done and _knock_bounced and is_on_floor() and _knock_vel.y >= -0.01
	if not landed:
		return

	if is_dead:
		# 半空被打死：落地即成尸体，后续交给 _update_corpse
		# （这里不重播死亡动画，否则身体会从躺平跳回站立再倒一次）
		is_knocked = false
		state = State.DEAD
		_begin_corpse_timers()
		return

	_down_timer += delta
	if _down_timer >= down_time / _speed_mult():
		_get_up()

## 起身：把死亡动画倒放（躺平 → 站立），比硬切待机自然。
## 期间保持 is_knocked，好让 _update_launched 继续把模型高度抬回正常，起身结束才归零。
func _get_up() -> void:
	_getting_up = true
	_down_timer = 0.0
	state = State.CHASE
	if not animation_player.has_animation(DEATH_ANIM):
		_getting_up = false
		is_knocked = false
		model.position.y = 0.0
		play_animation(RUN_ANIM)
		return
	animation_player.play(DEATH_ANIM)
	animation_player.seek(DEATH_FREEZE_T, true)
	animation_player.speed_scale = getup_speed * _speed_mult()
	animation_player.play_backwards(DEATH_ANIM)   # 从定格处倒放到站立
	var dur: float = DEATH_FREEZE_T / (getup_speed * _speed_mult())
	await get_tree().create_timer(dur).timeout
	_getting_up = false
	is_knocked = false
	model.position.y = 0.0   # 保险：起完身完全归位
	if not is_dead:
		state = State.CHASE
		play_animation(RUN_ANIM)

## 开局预备动作：拔剑/收剑（SheathSword2），播完才进入正常 AI。
## 同时把技能冷却重置为满，避免起手刚结束就一个旋风劈冲过来。
func _start_intro() -> void:
	if not animation_player.has_animation(SHEATH_ANIM):
		play_animation(IDLE_ANIM)
		return
	_intro_active = true
	state = State.INTRO
	skill_timer = skill_cooldown
	play_animation(SHEATH_ANIM)
	var anim: Animation = animation_player.get_animation(SHEATH_ANIM)
	var dur: float = (anim.length if anim else 0.87) / _speed_mult()
	await get_tree().create_timer(dur).timeout
	_intro_active = false
	if not is_dead and not is_knocked:
		state = State.IDLE
		play_animation(IDLE_ANIM)

func _update_intro(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, _spd() * 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, _spd() * 10.0 * delta)
	# 起手时面向玩家（看得到才转身），但不出脚、不出手
	var p: Node3D = get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p):
		var to_p: Vector3 = p.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.0001:
			rotation.y = lerp_angle(rotation.y, atan2(to_p.x, to_p.z), 6.0 * delta)
	move_and_slide()

func play_animation(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		animation_player.speed_scale = _speed_mult()
		animation_player.play(anim_name)
	else:
		print("敌人动画不存在: ", anim_name)

# 全局倍速辅助：敌人移动/动画/计时统一跟随 SpeedMode（F 切换 1x/2x）
func _speed_mult() -> float:
	return SpeedMode.factor

func _spd() -> float:
	return move_speed * _speed_mult()

func _grav() -> float:
	return gravity * _speed_mult() * _speed_mult()

func _on_speed_mode_changed(_factor: float) -> void:
	animation_player.speed_scale = _speed_mult()
