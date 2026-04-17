extends Node3D
class_name VideoMeshStereo

## Stereo 3D video görüntüleyici
## Sol ve sağ mesh'e aynı texture'ı pseudo-stereo shift ile basar.
## Tek kameradan gelir, IPD kadar shift uygulanır.

@export_group("Mesh Boyutları")
@export var mesh_width:    float = 1.6   # metre
@export var mesh_height:   float = 0.9
@export var mesh_distance: float = 2.0  # kameradan uzaklık

@export_group("Stereo Ayarları")
@export var ipd_meters:         float = 0.064   # Interpupillary distance
@export var stereo_shift_uv:    float = 0.03    # UV shift miktarı
@export var stereo_zoom:        float = 1.02
@export var enable_pseudo_stereo: bool = true

@export_group("Video Kaynağı")
@export var receiver_path: NodePath
@export var port:   int  = 5010
@export var width:  int  = 1280
@export var height: int  = 720

@export_group("Debug")
@export var show_debug_overlay: bool = true
@export var show_wireframe:     bool = false

# Sahne node'ları
var _left_mesh:  MeshInstance3D
var _right_mesh: MeshInstance3D
var _left_mat:   ShaderMaterial
var _right_mat:  ShaderMaterial

var _receiver   = null
var _retry_timer := 0.0

var _debug_label: Label3D
var _fps_display := 0.0

const STEREO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D video_texture : source_color, filter_linear;
uniform float shift_uv  = 0.0;
uniform float zoom_uv   = 1.0;
uniform float brightness = 1.0;

void fragment() {
    vec2 uv = (UV - vec2(0.5)) / max(zoom_uv, 0.001) + vec2(0.5 + shift_uv, 0.5);

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        ALBEDO = vec3(0.0);
        ALPHA  = 1.0;
    } else {
        vec4 col = texture(video_texture, uv);
        ALBEDO = col.rgb * brightness;
        ALPHA  = 1.0;
    }
}
"""

func _ready() -> void:
	_build_stereo_meshes()
	_setup_debug_overlay()
	_setup_receiver()

func _build_stereo_meshes() -> void:
	var quad = QuadMesh.new()
	quad.size = Vector2(mesh_width, mesh_height)

	# Shader
	var shader = Shader.new()
	shader.code = STEREO_SHADER

	_left_mat = ShaderMaterial.new()
	_left_mat.shader = shader

	_right_mat = ShaderMaterial.new()
	_right_mat.shader = shader

	# Sol mesh - kamera sol gözü simüle eder
	_left_mesh = MeshInstance3D.new()
	_left_mesh.name = "LeftMesh"
	_left_mesh.mesh = quad
	_left_mesh.material_override = _left_mat
	_left_mesh.position = Vector3(-ipd_meters * 0.5, 0.0, -mesh_distance)
	add_child(_left_mesh)

	# Sağ mesh
	_right_mesh = MeshInstance3D.new()
	_right_mesh.name = "RightMesh"
	_right_mesh.mesh = quad
	_right_mesh.material_override = _right_mat
	_right_mesh.position = Vector3(ipd_meters * 0.5, 0.0, -mesh_distance)
	add_child(_right_mesh)

	# Başlangıç parametreleri
	_update_stereo_params()

	_log("Mesh'ler oluşturuldu: %.2fx%.2f @ %.2fm" % [mesh_width, mesh_height, mesh_distance])

func _update_stereo_params() -> void:
	if not enable_pseudo_stereo:
		_left_mat.set_shader_parameter("shift_uv",  0.0)
		_right_mat.set_shader_parameter("shift_uv", 0.0)
		_left_mat.set_shader_parameter("zoom_uv",   1.0)
		_right_mat.set_shader_parameter("zoom_uv",  1.0)
		return

	_left_mat.set_shader_parameter("shift_uv",  -stereo_shift_uv)
	_right_mat.set_shader_parameter("shift_uv",  stereo_shift_uv)
	_left_mat.set_shader_parameter("zoom_uv",    stereo_zoom)
	_right_mat.set_shader_parameter("zoom_uv",   stereo_zoom)

func _setup_receiver() -> void:
	# Dış receiver node mu var, yoksa kendi oluşturur mu?
	if not receiver_path.is_empty():
		_receiver = get_node_or_null(receiver_path)

	if _receiver == null:
		var recv_script = load("res://addons/external_texture/ExternalTextureReceiver.gd")
		if recv_script == null:
			_log("Receiver script yüklenemedi: res://addons/external_texture/ExternalTextureReceiver.gd")
			return
		_receiver = recv_script.new()

		if _receiver == null:
			_log("Receiver oluşturulamadı")
			return

		_receiver.name       = "VideoReceiver"
		_receiver.port       = port
		_receiver.width      = width
		_receiver.height     = height
		# Sinyal kaçırmamak için auto-start kapalı, bağlantıdan sonra elle başlat.
		_receiver.auto_start = false
		add_child(_receiver)

	if _receiver.has_signal("texture_ready") and not _receiver.texture_ready.is_connected(_on_texture_ready):
		_receiver.texture_ready.connect(_on_texture_ready)
	if _receiver.has_signal("fps_updated") and not _receiver.fps_updated.is_connected(_on_fps_updated):
		_receiver.fps_updated.connect(_on_fps_updated)

	if _receiver.has_method("is_receiving") and _receiver.has_method("start_receiving") and not _receiver.is_receiving():
		var started: bool = _receiver.start_receiving()
		if not started:
			var err: String = _receiver.get_last_error() if _receiver.has_method("get_last_error") else "(hata alınamadı)"
			_log("Receiver start başarısız: %s" % err)

	# Receiver çok hızlı başlarsa texture_ready sinyali kaçmış olabilir.
	var tex = _receiver.get_texture() if _receiver.has_method("get_texture") else null
	if tex != null:
		_on_texture_ready(tex)

	_log("Receiver bağlandı")

func _on_texture_ready(tex: Texture2D) -> void:
	if tex == null:
		return
	_left_mat.set_shader_parameter("video_texture",  tex)
	_right_mat.set_shader_parameter("video_texture", tex)
	_log("Texture mesh'lere bağlandı")

func _on_fps_updated(fps: float) -> void:
	_fps_display = fps

func _setup_debug_overlay() -> void:
	if not show_debug_overlay:
		return

	_debug_label = Label3D.new()
	_debug_label.name = "DebugOverlay"
	_debug_label.position = Vector3(0.0, mesh_height * 0.5 + 0.15, -mesh_distance)
	_debug_label.font_size = 32
	_debug_label.modulate = Color.YELLOW
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_debug_label)

func _process(_delta: float) -> void:
	if _receiver == null:
		_retry_timer += _delta
		if _retry_timer >= 1.0:
			_retry_timer = 0.0
			_setup_receiver()
	elif _receiver.has_method("is_receiving") and _receiver.has_method("start_receiving") and not _receiver.is_receiving():
		_retry_timer += _delta
		if _retry_timer >= 1.0:
			_retry_timer = 0.0
			_receiver.start_receiving()

	if _debug_label == null and show_debug_overlay:
		_setup_debug_overlay()

	if _debug_label == null or not show_debug_overlay:
		return

	_debug_label.visible = true

	var test_mode := false
	if _receiver != null:
		test_mode = _receiver.get("_test_mode") == true
	var src := "ANDROID" if not test_mode else "TEST"
	var node_state := "OK" if _receiver != null else "NULL"
	var recv_state := "ON" if (_receiver != null and _receiver.has_method("is_receiving") and _receiver.is_receiving()) else "OFF"
	var err_text := ""
	if _receiver != null and _receiver.has_method("get_last_error"):
		err_text = _receiver.get_last_error()
	var err_short := "-"
	if err_text != "":
		if err_text.find("Texture slotu") >= 0:
			err_short = "SLOT"
		elif err_text.find("SurfaceTexture null") >= 0:
			err_short = "SURF"
		elif err_text.find("MediaCodecReceiver başlatılamadı") >= 0:
			err_short = "MCSTART"
		elif err_text.find("Geçersiz GL texture id") >= 0:
			err_short = "GLID"
		elif err_text.find("MediaCodecReceiver/bridge") >= 0:
			err_short = "BRIDGE"
		else:
			err_short = "OTHER"
	if _receiver == null:
		err_short = "NODE"
	if err_text.length() > 42:
		err_text = err_text.substr(0, 42) + "..."
	_debug_label.text = (
		"FPS: %.1f  |  SRC: %s\n" % [_fps_display, src] +
		"PORT: %d  %dx%d  NODE:%s  RECV:%s  ERR:%s\n" % [port, width, height, node_state, recv_state, err_short] +
		"SHIFT: %.3f  ZOOM: %.3f\n" % [stereo_shift_uv, stereo_zoom] +
		"ERR: %s\n" % err_text +
		"[+/-] shift  [Z/X] zoom  [S] stereo toggle"
	)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_PLUS, KEY_EQUAL:
				stereo_shift_uv = clampf(stereo_shift_uv + 0.005, 0.0, 0.2)
				_update_stereo_params()
			KEY_MINUS:
				stereo_shift_uv = clampf(stereo_shift_uv - 0.005, 0.0, 0.2)
				_update_stereo_params()
			KEY_Z:
				stereo_zoom = clampf(stereo_zoom + 0.01, 0.9, 1.5)
				_update_stereo_params()
			KEY_X:
				stereo_zoom = clampf(stereo_zoom - 0.01, 0.9, 1.5)
				_update_stereo_params()
			KEY_S:
				enable_pseudo_stereo = not enable_pseudo_stereo
				_update_stereo_params()
			KEY_R:
				if _receiver:
					_receiver.stop_receiving()
					await get_tree().create_timer(0.3).timeout
					_receiver.start_receiving()
			KEY_D:
				show_debug_overlay = not show_debug_overlay
				if _debug_label:
					_debug_label.visible = show_debug_overlay

func _log(msg: String) -> void:
	print("[VideoMeshStereo] " + msg)

func _exit_tree() -> void:
	if _receiver and _receiver.has_method("stop_receiving"):
		_receiver.stop_receiving()
