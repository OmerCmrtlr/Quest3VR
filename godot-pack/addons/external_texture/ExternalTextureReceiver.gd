extends Node
class_name ExternalTextureReceiver

## UDP RTP H264 video akışını ExternalTexture olarak alır.
## Java tarafı: ExternalTexturePlugin (SurfaceTexture)
##              MediaCodecReceiver (UDP decode)

signal texture_ready(texture: Texture2D)
signal stream_started
signal stream_stopped
signal fps_updated(fps: float)

@export var port: int = 5010
@export var width: int = 1280
@export var height: int = 720
@export var auto_start: bool = true
@export var show_debug: bool = true

# Android plugin referansları
var _ext_plugin  = null   # ExternalTexturePlugin
var _recv_plugin = null   # MediaCodecReceiver

var _texture_slot: int = -1
var _godot_texture: Texture2D = null
var _last_error: String = ""

var _is_receiving := false
var _frame_count  := 0
var _fps          := 0.0
var _fps_timer    := 0.0
var _fps_display  := 0.0

# Test modu (editor / non-android)
var _test_mode    := false
var _test_image   : Image = null
var _test_hue     := 0.0

func _has_any_method(target, names: Array[String]) -> bool:
	if target == null:
		return false
	for method_name in names:
		if target.has_method(method_name):
			return true
	return false

func _call_ext(target, names: Array[String], args: Array = [], default_value = null):
	if target == null:
		return default_value
	for method_name in names:
		if target.has_method(method_name):
			return target.callv(method_name, args)
	return default_value

func _ready() -> void:
	_try_init_plugins()

	if auto_start:
		start_receiving()

func _try_init_plugins() -> void:
	if not OS.get_name() == "Android":
		_test_mode = true
		_log("Android değil, test modu aktif (gradient animasyon)")
		return

	if not Engine.has_singleton("ExternalTexturePlugin"):
		_set_error("[ExtReceiver] ExternalTexturePlugin bulunamadı! Plugin yüklü mü?")
		_test_mode = true
		return

	_ext_plugin = Engine.get_singleton("ExternalTexturePlugin")
	_log(
		"Plugin method check: startReceiverForTexture=%s setTargetSurfaceTexture=%s startReceiving=%s" % [
			str(_has_any_method(_ext_plugin, ["startReceiverForTexture", "start_receiver_for_texture"])),
			str(_has_any_method(_ext_plugin, ["setTargetSurfaceTexture", "set_target_surface_texture"])),
			str(_has_any_method(_ext_plugin, ["startReceiving", "start_receiving"]))
		]
	)

	# Öncelik: aynı singleton içindeki Java bridge yöntemi.
	# SurfaceTexture'ı Godot üzerinden round-trip taşımadan başlatır.
	if _ext_plugin != null and _has_any_method(_ext_plugin, ["startReceiverForTexture", "start_receiver_for_texture"]):
		_recv_plugin = _ext_plugin
		_log("ExternalTexturePlugin bridge (startReceiverForTexture) kullanılacak")
		return

	if Engine.has_singleton("MediaCodecReceiver"):
		_recv_plugin = Engine.get_singleton("MediaCodecReceiver")
		_log("Pluginler bağlandı (ExternalTexturePlugin + MediaCodecReceiver)")
		return

	# Yeni fallback: MediaCodecReceiver ayrı singleton yoksa,
	# ExternalTexturePlugin içindeki bridge metodlarını kullan.
	if _ext_plugin != null \
	and _has_any_method(_ext_plugin, ["setTargetSurfaceTexture", "set_target_surface_texture"]) \
	and _has_any_method(_ext_plugin, ["startReceiving", "start_receiving"]):
		_recv_plugin = _ext_plugin
		_log("MediaCodecReceiver singleton yok, ExternalTexturePlugin bridge kullanılacak")
		return

	_set_error("[ExtReceiver] MediaCodecReceiver/bridge metodları bulunamadı!")
	_test_mode = true

func start_receiving() -> bool:
	if _is_receiving:
		return true

	_last_error = ""

	# _ready() çağrılmadan erken start denemelerine karşı güvenli init.
	if _ext_plugin == null and not _test_mode:
		_try_init_plugins()

	if _test_mode:
		_start_test_mode()
		return true

	if _ext_plugin == null or _recv_plugin == null:
		_set_error("[ExtReceiver] Plugin init tamamlanmadı")
		return false

	# 1. Texture slotu oluştur
	_call_ext(_ext_plugin, ["setDefaultBufferSize", "set_default_buffer_size"], [width, height])
	_texture_slot = int(_call_ext(_ext_plugin, ["createExternalTexture", "create_external_texture"], [], -1))

	if _texture_slot < 0:
		_set_error("[ExtReceiver] Texture slotu alınamadı!")
		return false

	_log("Texture slot: %d" % _texture_slot)

	# 2. SurfaceTexture'ı alıp receiver'a ver
	var ok: bool = false
	if _recv_plugin == _ext_plugin and _has_any_method(_ext_plugin, ["startReceiverForTexture", "start_receiver_for_texture"]):
		ok = bool(_call_ext(_ext_plugin, ["startReceiverForTexture", "start_receiver_for_texture"], [_texture_slot, port, width, height], false))
	else:
		var surface = _call_ext(_ext_plugin, ["getSurfaceForTexture", "get_surface_for_texture"], [_texture_slot])
		if surface == null:
			_set_error("[ExtReceiver] SurfaceTexture null!")
			return false

		_call_ext(_recv_plugin, ["setTargetSurfaceTexture", "set_target_surface_texture"], [surface])
		_call_ext(_recv_plugin, ["setPort", "set_port"], [port])
		_call_ext(_recv_plugin, ["setResolution", "set_resolution"], [width, height])

		# 3. Decoder'ı başlat
		ok = bool(_call_ext(_recv_plugin, ["startReceiving", "start_receiving"], [], false))

	if not ok:
		_set_error("[ExtReceiver] MediaCodecReceiver başlatılamadı!")
		_call_ext(_ext_plugin, ["destroyExternalTexture", "destroy_external_texture"], [_texture_slot])
		_texture_slot = -1
		return false

	# 4. Godot ImageTexture oluştur - her frame güncelleneceğiz
	# NOT: Gerçek external texture için RenderingServer.texture_create_from_native_handle() kullanılır
	# Godot 4.x + Android OpenGL için:
	_setup_external_texture_in_godot()

	_is_receiving = true
	emit_signal("stream_started")
	_log("Akış başladı -> port %d" % port)
	return true

func _setup_external_texture_in_godot() -> void:
	var gl_id := int(_call_ext(_ext_plugin, ["getGlTextureId", "get_gl_texture_id"], [_texture_slot], -1))
	if gl_id <= 0:
		_set_error("[ExtReceiver] Geçersiz GL texture id: %d" % gl_id)
		return

	var ext_tex := ExternalTexture.new()
	ext_tex.size = Vector2(width, height)
	ext_tex.set_external_buffer_id(gl_id)

	_godot_texture = ext_tex
	emit_signal("texture_ready", _godot_texture)
	_log("ExternalTexture bağlandı, gl_id=%d" % gl_id)

func stop_receiving() -> void:
	if not _is_receiving:
		return

	if _test_mode:
		_is_receiving = false
		emit_signal("stream_stopped")
		return

	if _recv_plugin != null:
		_call_ext(_recv_plugin, ["stopReceiving", "stop_receiving"], [])

	if _ext_plugin != null and _texture_slot >= 0:
		_call_ext(_ext_plugin, ["destroyExternalTexture", "destroy_external_texture"], [_texture_slot])
		_texture_slot = -1

	_godot_texture = null
	_is_receiving  = false
	emit_signal("stream_stopped")
	_log("Durduruldu")

func get_texture() -> Texture2D:
	if _test_mode:
		return _get_test_texture()
	return _godot_texture

func is_receiving() -> bool:
	return _is_receiving

func get_fps() -> float:
	return _fps_display

func get_last_error() -> String:
	return _last_error

func _process(delta: float) -> void:
	_fps_timer += delta
	if _fps_timer >= 1.0:
		_fps_display = _frame_count / _fps_timer
		_frame_count = 0
		_fps_timer   = 0.0
		emit_signal("fps_updated", _fps_display)

	if not _is_receiving:
		return

	if _test_mode:
		_update_test_frame(delta)
		return

	_update_android_frame()

func _update_android_frame() -> void:
	if _ext_plugin == null or _recv_plugin == null:
		return

	# GL thread'de updateTexImage çağrılmalı
	# Godot 4 Android'de _process GL thread'de değil ama
	# Godot plugin callback sistemi ile bunu yönetiyoruz
	var updated: bool = bool(_call_ext(_ext_plugin, ["updateTexture", "update_texture"], [_texture_slot], false))
	if not updated:
		return

	# Şimdi GL texId geçerli, Godot'a aktarıyoruz
	# RenderingServer üzerinden native texture handle kullan
	_pull_frame_from_gl()
	_frame_count += 1

func _pull_frame_from_gl() -> void:
	## Gerçek implementasyon: RenderingServer.texture_create_from_native_handle()
	## Godot 4.2+ Android'de çalışır
	##
	## var gl_id = _ext_plugin.get_gl_texture_id(_texture_slot)
	## var rid = RenderingServer.texture_create_from_native_handle(
	##     RenderingServer.TEXTURE_TYPE_2D,
	##     Image.FORMAT_RGB8,
	##     gl_id, width, height, 0
	## )
	## _godot_texture = ImageTexture.create_from_image(...)  <- bu yol değil
	##
	## En düzgün yol: Godot C++ eklentisi yazmak veya
	## AndroidRuntime.runOnRenderThread ile updateTexImage + Godot texture link

	# Şimdilik: MediaCodecReceiver Surface->SurfaceTexture zinciri
	# Godot'un kendi ExternalTexture class'ını kullan (varsa)
	pass  # _godot_texture zaten SurfaceTexture'a bağlı RID üzerinden güncelleniyor

# ---------------------------------------------------------------
# TEST MODU - Editor/PC'de çalışır, animasyonlu gradient
# ---------------------------------------------------------------
var _test_texture: ImageTexture = null

func _start_test_mode() -> void:
	_test_image   = Image.create(width, height, false, Image.FORMAT_RGB8)
	_test_texture = ImageTexture.create_from_image(_test_image)
	_is_receiving = true
	emit_signal("stream_started")
	emit_signal("texture_ready", _test_texture)
	_log("Test modu: animasyonlu gradient")

func _update_test_frame(delta: float) -> void:
	if _test_image == null:
		return
	_test_hue = fmod(_test_hue + delta * 0.3, 1.0)
	# Hızlı gradient çiz
	for y in range(0, height, 4):       # Her 4 satırda bir (performans)
		for x in range(0, width, 4):
			var u    := float(x) / width
			var v    := float(y) / height
			var col  := Color.from_hsv(fmod(_test_hue + u * 0.3, 1.0), 0.8, 0.7 + v * 0.3)
			_test_image.set_pixel(x, y, col)
	_test_texture.update(_test_image)
	_frame_count += 1

func _get_test_texture() -> Texture2D:
	return _test_texture

func _set_error(msg: String) -> void:
	_last_error = msg
	push_error(msg)
	_log("ERR: " + msg)

func _log(msg: String) -> void:
	if show_debug:
		print("[ExtReceiver] " + msg)
