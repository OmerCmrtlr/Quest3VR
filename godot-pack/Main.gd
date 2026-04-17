extends Node3D

## Quest3 / Android Tablet stereo video görüntüleyici
## Ana sahne kontrolcüsü

@export var video_port:   int   = 5010
@export var video_width:  int   = 1280
@export var video_height: int   = 720
@export var mesh_dist:    float = 2.0

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
	_stereo_viewer.mesh_width     = 1.78  # 16:9 oran
	_stereo_viewer.mesh_height    = 1.0
	_stereo_viewer.show_debug_overlay = true
	add_child(_stereo_viewer)

func _log(msg: String) -> void:
	print("[Main] " + msg)
