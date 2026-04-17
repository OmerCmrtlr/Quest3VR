extends Node
class_name ExternalTextureReceiver

signal texture_ready(texture: Texture2D)
signal stream_started
signal stream_stopped
signal fps_updated(fps: float)

@export var port: int = 5010
@export var width: int = 1280
@export var height: int = 720
@export var auto_start: bool = true
@export var show_debug: bool = true

var _udp: PacketPeerUDP = null
var _godot_texture: ImageTexture = null
var _image: Image = null
var _last_error: String = ""
var _is_receiving := false
var _frame_count := 0
var _fps_timer := 0.0
var _fps_display := 0.0

# RTP reassembly
var _rtp_frags: Dictionary = {}
var _last_seq: int = -1

func _ready() -> void:
	if auto_start:
		start_receiving()

func start_receiving() -> bool:
	if _is_receiving:
		return true
	_last_error = ""

	_udp = PacketPeerUDP.new()
	var err = _udp.bind(port, "0.0.0.0")
	if err != OK:
		_set_error("UDP bind hatası port=%d err=%d" % [port, err])
		_udp = null
		return false

	_image = Image.create(width, height, false, Image.FORMAT_RGB8)
	_godot_texture = ImageTexture.create_from_image(_image)

	_is_receiving = true
	emit_signal("stream_started")
	emit_signal("texture_ready", _godot_texture)
	_log("UDP dinleniyor port=%d" % port)
	return true

func stop_receiving() -> void:
	if not _is_receiving:
		return
	_is_receiving = false
	if _udp != null:
		_udp.close()
		_udp = null
	emit_signal("stream_stopped")
	_log("Durduruldu")

func get_texture() -> Texture2D:
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
		_fps_display = float(_frame_count) / _fps_timer
		_frame_count = 0
		_fps_timer = 0.0
		emit_signal("fps_updated", _fps_display)

	if not _is_receiving or _udp == null:
		return

	var count = _udp.get_available_packet_count()
	var processed = 0
	while processed < 8 and _udp.get_available_packet_count() > 0:
		var data: PackedByteArray = _udp.get_packet()
		if data.size() > 0:
			_process_packet(data)
		processed += 1

func _process_packet(data: PackedByteArray) -> void:
	var size = data.size()

	# RTP header minimum 12 byte
	if size < 13:
		return

	# RTP header parse
	var version = (data[0] >> 6) & 0x03
	if version != 2:
		return

	var has_padding = (data[0] & 0x20) != 0
	var has_extension = (data[0] & 0x10) != 0
	var cc = data[0] & 0x0F
	var marker = (data[1] & 0x80) != 0
	var payload_type = data[1] & 0x7F
	var seq = (data[2] << 8) | data[3]
	var timestamp = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7]

	var payload_start = 12 + cc * 4
	if has_extension:
		if payload_start + 4 > size:
			return
		var ext_len = (data[payload_start + 2] << 8) | data[payload_start + 3]
		payload_start += 4 + ext_len * 4

	if payload_start >= size:
		return

	# JPEG RTP (PT=26) - basit, doğrudan JPEG
	if payload_type == 26:
		_handle_rtp_jpeg(data, payload_start, size, marker, timestamp)
		return

	# H264 RTP (PT=96)
	if payload_type == 96:
		_handle_rtp_h264(data, payload_start, size, marker, seq, timestamp)
		return

func _handle_rtp_jpeg(data: PackedByteArray, offset: int, size: int, marker: bool, ts: int) -> void:
	# RTP JPEG header: Type Offset(3) Type Quality Width Height
	if offset + 8 > size:
		return

	var frag_offset = (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]
	var jpeg_type = data[offset + 4]
	var quality = data[offset + 5]
	var img_w = data[offset + 6] * 8
	var img_h = data[offset + 7] * 8
	var payload_offset = offset + 8

	# Quantization tables (quality >= 128)
	if quality >= 128:
		if payload_offset + 4 > size:
			return
		var qt_len = (data[payload_offset + 2] << 8) | data[payload_offset + 3]
		payload_offset += 4 + qt_len

	if payload_offset >= size:
		return

	if not _rtp_frags.has(ts):
		_rtp_frags[ts] = {}

	var frag_data = data.slice(payload_offset, size)
	_rtp_frags[ts][frag_offset] = frag_data

	if marker:
		# Tüm fragment'lar geldi, JPEG oluştur
		var frame_data = PackedByteArray()
		var jpeg_header = _build_jpeg_header(img_w if img_w > 0 else width,
										 img_h if img_h > 0 else height,
										 quality, jpeg_type)
		frame_data.append_array(jpeg_header)

		var offsets = _rtp_frags[ts].keys()
		offsets.sort()
		for off in offsets:
			frame_data.append_array(_rtp_frags[ts][off])

		# JPEG EOI
		frame_data.append(0xFF)
		frame_data.append(0xD9)

		_rtp_frags.erase(ts)
		_decode_jpeg(frame_data)

func _handle_rtp_h264(data: PackedByteArray, offset: int, size: int, marker: bool, seq: int, ts: int) -> void:
	if offset >= size:
		return

	var nal_header = data[offset]
	var nal_type = nal_header & 0x1F

	if nal_type >= 1 and nal_type <= 23:
		# Single NAL
		var nal = data.slice(offset, size)
		if not _rtp_frags.has(ts):
			_rtp_frags[ts] = []
		_rtp_frags[ts].append(nal)
		if marker:
			_flush_h264_frame(ts)

	elif nal_type == 28:
		# FU-A
		if offset + 2 > size:
			return
		var fu_header = data[offset + 1]
		var is_start = (fu_header & 0x80) != 0
		var is_end = (fu_header & 0x40) != 0
		var fu_nal_type = fu_header & 0x1F

		var reconstructed_header = (nal_header & 0xE0) | fu_nal_type
		var payload = data.slice(offset + 2, size)

		var key = str(ts) + "_fu"
		if is_start:
			var chunk = PackedByteArray()
			chunk.append(reconstructed_header)
			chunk.append_array(payload)
			_rtp_frags[key] = chunk
		elif _rtp_frags.has(key):
			_rtp_frags[key].append_array(payload)

		if is_end and _rtp_frags.has(key):
			var nal = _rtp_frags[key]
			_rtp_frags.erase(key)
			if not _rtp_frags.has(ts):
				_rtp_frags[ts] = []
			_rtp_frags[ts].append(nal)
			if marker:
				_flush_h264_frame(ts)

	elif nal_type == 24:
		# STAP-A
		var pos = offset + 1
		while pos + 2 <= size:
			var nal_size = (data[pos] << 8) | data[pos + 1]
			pos += 2
			if pos + nal_size > size:
				break
			var nal = data.slice(pos, pos + nal_size)
			if not _rtp_frags.has(ts):
				_rtp_frags[ts] = []
			_rtp_frags[ts].append(nal)
			pos += nal_size
		if marker:
			_flush_h264_frame(ts)

func _flush_h264_frame(ts: int) -> void:
	if not _rtp_frags.has(ts):
		return
	# H264 Godot'ta doğrudan decode edilemiyor
	# Bu yüzden MJPEG kullanacağız (sender tarafını değiştireceğiz)
	_rtp_frags.erase(ts)

func _decode_jpeg(jpeg_data: PackedByteArray) -> void:
	if _image == null:
		_image = Image.create(width, height, false, Image.FORMAT_RGB8)

	var img = Image.new()
	var err = img.load_jpg_from_buffer(jpeg_data)
	if err != OK:
		_set_error("JPEG decode hata: %d" % err)
		return

	if img.get_width() != width or img.get_height() != height:
		img.resize(width, height, Image.INTERPOLATION_BILINEAR)

	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)

	_image = img
	if _godot_texture == null:
		_godot_texture = ImageTexture.create_from_image(_image)
		emit_signal("texture_ready", _godot_texture)
	else:
		_godot_texture.update(_image)

	_frame_count += 1

func _build_jpeg_header(w: int, h: int, quality: int, type: int) -> PackedByteArray:
	# Minimal JPEG SOI + APP0 header
	# GStreamer rtpjpegpay payload zaten tam JPEG header içermiyor
	# Basit SOI marker yeterli değil, minimal header gerekiyor
	var q = clampi(quality, 1, 99)
	var scale = (5000.0 / q) if q < 50 else (200.0 - q * 2.0)

	# Standart luminance quantization table
	var lum_qt = [
		16,11,10,16,24,40,51,61,
		12,12,14,19,26,58,60,55,
		14,13,16,24,40,57,69,56,
		14,17,22,29,51,87,80,62,
		18,22,37,56,68,109,103,77,
		24,35,55,64,81,104,113,92,
		49,64,78,87,103,121,120,101,
		72,92,95,98,112,100,103,99
	]
	# Standart chrominance quantization table
	var chrom_qt = [
		17,18,24,47,99,99,99,99,
		18,21,26,66,99,99,99,99,
		24,26,56,99,99,99,99,99,
		47,66,99,99,99,99,99,99,
		99,99,99,99,99,99,99,99,
		99,99,99,99,99,99,99,99,
		99,99,99,99,99,99,99,99,
		99,99,99,99,99,99,99,99
	]

	var hdr = PackedByteArray()
	# SOI
	hdr.append(0xFF); hdr.append(0xD8)
	# APP0 JFIF
	hdr.append(0xFF); hdr.append(0xE0)
	hdr.append(0x00); hdr.append(0x10)
	hdr.append_array([0x4A,0x46,0x49,0x46,0x00,0x01,0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00])
	# DQT Luminance
	hdr.append(0xFF); hdr.append(0xDB)
	hdr.append(0x00); hdr.append(0x43)
	hdr.append(0x00)
	for v in lum_qt:
		var sv = int(clampi(int(v * scale / 100.0), 1, 255))
		hdr.append(sv)
	# DQT Chrominance
	hdr.append(0xFF); hdr.append(0xDB)
	hdr.append(0x00); hdr.append(0x43)
	hdr.append(0x01)
	for v in chrom_qt:
		var sv = int(clampi(int(v * scale / 100.0), 1, 255))
		hdr.append(sv)
	return hdr

func _set_error(msg: String) -> void:
	_last_error = msg
	push_error("[ExtReceiver] " + msg)
	_log("ERR: " + msg)

func _log(msg: String) -> void:
	if show_debug:
		print("[ExtReceiver] " + msg)
