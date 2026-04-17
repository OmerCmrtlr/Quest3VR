extends Node3D

## Quest3 / Android Tablet stereo video görüntüleyici
## Ana sahne kontrolcüsü

@export var video_port:   int   = 5010
@export var video_width:  int   = 1280
@export var video_height: int   = 720
@export var mesh_dist:    float = 2.0
@export var fit_mesh_to_screen: bool = true
@export var mesh_fill_scale: float = 1.03

var _stereo_viewer: VideoMeshStereo
var _camera_left:   Camera3D
var _camera_right:  Camera3D
var _env_world:     WorldEnvironment

func _ready() -> void:
	_setup_world()
	_setup_cameras()
	_setup_stereo_video()
	_log("Sahne hazır")

func _setup_world() -> void:
	# Siyah arkaplan - video tam dolacak
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color.WHITE
	env.ambient_light_energy = 1.0

	_env_world = WorldEnvironment.new()
	_env_world.environment = env
	add_child(_env_world)

func _setup_cameras() -> void:
	# Quest3 / Tablet için tek kamera (tablet stereo yok, tek viewport)
	# Quest3 OVR için ayrı kamera setup gerekir (XR plugin ile)
	var cam = Camera3D.new()
	cam.name     = "MainCamera"
	cam.position = Vector3.ZERO
	cam.fov      = 90.0
	# Near plane çok küçük - mesh yakın yerleştirildiğinde clipping olmaması için
	cam.near     = 0.01
	cam.far      = 100.0
	add_child(cam)
	_camera_left = cam

func _setup_stereo_video() -> void:
	_stereo_viewer = VideoMeshStereo.new()
	_stereo_viewer.name           = "StereoViewer"
	_stereo_viewer.port           = video_port
	_stereo_viewer.width          = video_width
	_stereo_viewer.height         = video_height
	_stereo_viewer.mesh_distance  = mesh_dist

	var target_size := Vector2(1.78, 1.0)
	if fit_mesh_to_screen:
		target_size = _compute_fullscreen_mesh_size(mesh_dist)

	_stereo_viewer.mesh_width     = target_size.x
	_stereo_viewer.mesh_height    = target_size.y
	_stereo_viewer.show_debug_overlay = true
	add_child(_stereo_viewer)
	_log("Video mesh size: %.2fx%.2f @ %.2fm" % [target_size.x, target_size.y, mesh_dist])

func _compute_fullscreen_mesh_size(distance: float) -> Vector2:
	if _camera_left == null:
		return Vector2(1.78, 1.0)

	var vp_size = get_viewport().get_visible_rect().size
	var aspect := 16.0 / 9.0
	if vp_size.y > 0.0:
		aspect = float(vp_size.x) / float(vp_size.y)

	var safe_dist = maxf(distance, 0.05)
	var fov_rad = deg_to_rad(_camera_left.fov)
	var view_h = 2.0 * tan(fov_rad * 0.5) * safe_dist
	var view_w = view_h * aspect
	var scale = maxf(mesh_fill_scale, 1.0)

	return Vector2(view_w * scale, view_h * scale)

func _log(msg: String) -> void:
	print("[Main] " + msg)
