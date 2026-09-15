class_name ChargeVortex
extends Node3D

# 蓄力时脚下的浅蓝色漩涡：螺旋条纹由外向内流动、外缘随蓄力进度收窄、中心逐渐聚拢。
# 整个效果由一个极坐标着色器在贴地的圆盘上绘制，不依赖任何贴图资源。

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform float u_phase;      // 螺旋旋转/内收相位（脚本按蓄力进度变速累加）
uniform float u_wave;       // 同心波纹内收相位
uniform float u_progress;   // 蓄力进度 0~1
uniform float u_alpha;      // 整体透明度（淡入淡出）
uniform vec3 u_color : source_color = vec3(0.55, 0.85, 1.0);
uniform float u_arms = 3.0; // 螺旋臂数量

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;                 // 裁成圆形
	float ang = atan(p.y, p.x);

	// 外缘随蓄力由 1.0 收到 0.45 —— “由外至内收窄”（留一点尺寸保证蓄满时仍有力量感）
	float outer = mix(1.0, 0.45, u_progress);
	float inner = outer * 0.18;

	// 环带遮罩（只在这圈里画漩涡），蓄满时环带更粗更实
	float band = smoothstep(inner - 0.06, inner + 0.02, r)
			* (1.0 - smoothstep(outer - 0.12, outer, r));

	// 螺旋条纹：相位随时间增加 → 条纹向圆心流动
	float spiral = sin(u_arms * ang + r * 11.0 + u_phase) * 0.5 + 0.5;
	spiral = pow(spiral, 2.2);

	// 向内收缩的同心波纹
	float wave = sin(r * 26.0 + u_wave) * 0.5 + 0.5;

	// 外缘亮环 + 中心核心（随蓄力变亮变实）
	float rim = 1.0 - smoothstep(0.0, 0.10, abs(r - outer));
	float core = (1.0 - smoothstep(0.0, inner * 1.1, r)) * (0.35 + 1.15 * u_progress);

	float a = band * (0.28 + 0.72 * spiral) * (0.6 + 0.4 * wave) + rim * 0.55 + core * 0.85;
	ALBEDO = u_color * (1.0 + 2.2 * u_progress);   // 蓄满时更亮、更“高能”
	ALPHA = clamp(a * u_alpha, 0.0, 1.0);
}
"""

@export var color: Color = Color(0.55, 0.85, 1.0)  # 浅蓝
@export var full_color: Color = Color(1.0, 0.82, 0.3)  # 蓄满时转金色，给"可以放了"的反馈
@export var radius: float = 1.6                    # 漩涡盘半径（米）
@export var fade_speed: float = 4.0                # 淡入淡出速度

var _mat: ShaderMaterial
var _full_vec := Vector3(1.0, 0.82, 0.3)   # full_color 的 uniform 形式（_ready 里同步）
var _phase := 0.0
var _wave := 0.0
var _alpha := 0.0
var _target_alpha := 0.0
var _progress := 0.0

func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("u_color", Vector3(color.r, color.g, color.b))
	_mat.set_shader_parameter("u_arms", 3.0)
	_full_vec = Vector3(full_color.r, full_color.g, full_color.b)

	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = _mat
	# 注意：Godot 4 的 PlaneMesh 默认就躺在 XZ 平面上（AABB 为 x/z 有尺寸、y 为 0），
	# 已经与地面平行，千万不要再绕 X 轴旋转 —— 转了反而会立起来变成垂直于地面。
	mi.position.y = 0.02             # 略微抬起，避免与地面 z-fighting
	# 0 = 不投射阴影（Godot 4.7 的属性名是 cast_shadow，不是旧版的 cast_shadows）
	mi.cast_shadow = 0
	add_child(mi)

	# 注意：这里不要直接 visible=false —— 节点入树时 _ready 可能晚于 start() 执行，
	# 会把刚开启的特效又关掉。改为用 u_alpha=0 让它不可见，显隐统一由 _process 管理。
	_mat.set_shader_parameter("u_alpha", 0.0)

func start() -> void:
	# 开始蓄力：重置相位与进度，淡入
	visible = true
	_phase = 0.0
	_wave = 0.0
	_progress = 0.0
	_target_alpha = 1.0
	_apply_color(0.0)

func stop() -> void:
	# 松开/射出：淡出（到 0 后自动隐藏）
	_target_alpha = 0.0

func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	_apply_color(_progress)

## 蓄力进度 → 颜色：接近蓄满时由浅蓝渐变到金色
func _apply_color(p: float) -> void:
	if _mat == null:
		return
	var t: float = smoothstep(0.85, 1.0, p)
	var c: Vector3 = Vector3(color.r, color.g, color.b).lerp(_full_vec, t)
	_mat.set_shader_parameter("u_color", c)

func _process(delta: float) -> void:
	if not visible and _target_alpha == 0.0:
		return          # 未激活：不占用开销
	# 蓄得越满，旋转和内收越快，力量感更强
	_phase += delta * (2.5 + 8.0 * _progress)
	_wave += delta * (1.0 + 2.0 * _progress)
	_alpha = move_toward(_alpha, _target_alpha, delta * fade_speed)
	if _alpha <= 0.0 and _target_alpha == 0.0:
		visible = false
		return
	_mat.set_shader_parameter("u_phase", _phase)
	_mat.set_shader_parameter("u_wave", _wave)
	_mat.set_shader_parameter("u_progress", _progress)
	_mat.set_shader_parameter("u_alpha", _alpha)
