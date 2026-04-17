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

const _STD_LUMA_QT := [
	16,11,10,16,24,40,51,61,
	12,12,14,19,26,58,60,55,
	14,13,16,24,40,57,69,56,
	14,17,22,29,51,87,80,62,
	18,22,37,56,68,109,103,77,
	24,35,55,64,81,104,113,92,
	49,64,78,87,103,121,120,101,
	72,92,95,98,112,100,103,99
]

const _STD_CHROMA_QT := [
	17,18,24,47,99,99,99,99,
	18,21,26,66,99,99,99,99,
	24,26,56,99,99,99,99,99,
	47,66,99,99,99,99,99,99,
	99,99,99,99,99,99,99,99,
	99,99,99,99,99,99,99,99,
	99,99,99,99,99,99,99,99,
	99,99,99,99,99,99,99,99
]

const _DHT_DC_LUMA_BITS := [0x00,0x01,0x05,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x00,0x00,0x00]
const _DHT_DC_LUMA_VALS := [0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B]

const _DHT_AC_LUMA_BITS := [0x00,0x02,0x01,0x03,0x03,0x02,0x04,0x03,0x05,0x05,0x04,0x04,0x00,0x00,0x01,0x7D]
const _DHT_AC_LUMA_VALS := [
	0x01,0x02,0x03,0x00,0x04,0x11,0x05,0x12,0x21,0x31,0x41,0x06,0x13,0x51,0x61,0x07,
	0x22,0x71,0x14,0x32,0x81,0x91,0xA1,0x08,0x23,0x42,0xB1,0xC1,0x15,0x52,0xD1,0xF0,
	0x24,0x33,0x62,0x72,0x82,0x09,0x0A,0x16,0x17,0x18,0x19,0x1A,0x25,0x26,0x27,0x28,
	0x29,0x2A,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x43,0x44,0x45,0x46,0x47,0x48,0x49,
	0x4A,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x63,0x64,0x65,0x66,0x67,0x68,0x69,
	0x6A,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x83,0x84,0x85,0x86,0x87,0x88,0x89,
	0x8A,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,
	0xA8,0xA9,0xAA,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,0xB8,0xB9,0xBA,0xC2,0xC3,0xC4,0xC5,
	0xC6,0xC7,0xC8,0xC9,0xCA,0xD2,0xD3,0xD4,0xD5,0xD6,0xD7,0xD8,0xD9,0xDA,0xE1,0xE2,
	0xE3,0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xEA,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,
	0xF9,0xFA
]

const _DHT_DC_CHROMA_BITS := [0x00,0x03,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x00,0x00]
const _DHT_DC_CHROMA_VALS := [0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B]

const _DHT_AC_CHROMA_BITS := [0x00,0x02,0x01,0x02,0x04,0x04,0x03,0x04,0x07,0x05,0x04,0x04,0x00,0x01,0x02,0x77]
const _DHT_AC_CHROMA_VALS := [
	0x00,0x01,0x02,0x03,0x11,0x04,0x05,0x21,0x31,0x06,0x12,0x41,0x51,0x07,0x61,0x71,
	0x13,0x22,0x32,0x81,0x08,0x14,0x42,0x91,0xA1,0xB1,0xC1,0x09,0x23,0x33,0x52,0xF0,
	0x15,0x62,0x72,0xD1,0x0A,0x16,0x24,0x34,0xE1,0x25,0xF1,0x17,0x18,0x19,0x1A,0x26,
	0x27,0x28,0x29,0x2A,0x35,0x36,0x37,0x38,0x39,0x3A,0x43,0x44,0x45,0x46,0x47,0x48,
	0x49,0x4A,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x63,0x64,0x65,0x66,0x67,0x68,
	0x69,0x6A,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x82,0x83,0x84,0x85,0x86,0x87,
	0x88,0x89,0x8A,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0xA2,0xA3,0xA4,0xA5,
	0xA6,0xA7,0xA8,0xA9,0xAA,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,0xB8,0xB9,0xBA,0xC2,0xC3,
	0xC4,0xC5,0xC6,0xC7,0xC8,0xC9,0xCA,0xD2,0xD3,0xD4,0xD5,0xD6,0xD7,0xD8,0xD9,0xDA,
	0xE2,0xE3,0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xEA,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,
	0xF9,0xFA
]

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
	var parsed_luma_qt := PackedByteArray()
	var parsed_chroma_qt := PackedByteArray()

	# Quantization tables (quality >= 128)
	if quality >= 128:
		if payload_offset + 4 > size:
			return
		var qt_len = (data[payload_offset + 2] << 8) | data[payload_offset + 3]
		var qt_start = payload_offset + 4
		var qt_end = mini(size, qt_start + qt_len)
		if qt_end <= qt_start:
			return
		var qt_data = data.slice(qt_start, qt_end)
		payload_offset = qt_end

		if qt_data.size() >= 64:
			for i in range(64):
				parsed_luma_qt.append(qt_data[i])
			if qt_data.size() >= 128:
				for i in range(64):
					parsed_chroma_qt.append(qt_data[64 + i])
			else:
				parsed_chroma_qt = parsed_luma_qt

	if payload_offset >= size:
		return

	if not _rtp_frags.has(ts):
		_rtp_frags[ts] = {
			"frags": {},
			"quality": quality,
			"jpeg_type": jpeg_type,
			"img_w": img_w,
			"img_h": img_h,
			"luma_qt": PackedByteArray(),
			"chroma_qt": PackedByteArray()
		}

	var state: Dictionary = _rtp_frags[ts]
	var frags: Dictionary = state.get("frags", {})

	var frag_data = data.slice(payload_offset, size)
	frags[frag_offset] = frag_data
	state["frags"] = frags
	state["quality"] = quality
	state["jpeg_type"] = jpeg_type
	if img_w > 0:
		state["img_w"] = img_w
	if img_h > 0:
		state["img_h"] = img_h
	if parsed_luma_qt.size() >= 64:
		state["luma_qt"] = parsed_luma_qt
		state["chroma_qt"] = parsed_chroma_qt if parsed_chroma_qt.size() >= 64 else parsed_luma_qt
	_rtp_frags[ts] = state

	if marker:
		# Tüm fragment'lar geldi, JPEG entropy payload'ı birleştir
		var offsets = frags.keys()
		offsets.sort()
		if offsets.is_empty() or int(offsets[0]) != 0:
			_rtp_frags.erase(ts)
			return

		var entropy_payload := PackedByteArray()
		var expected_offset := 0
		for off in offsets:
			var off_i = int(off)
			var part: PackedByteArray = frags[off]
			if off_i != expected_offset:
				_rtp_frags.erase(ts)
				return
			entropy_payload.append_array(part)
			expected_offset += part.size()

		var frame_data = PackedByteArray()
		if entropy_payload.size() >= 2 and entropy_payload[0] == 0xFF and entropy_payload[1] == 0xD8:
			# Bazı kaynaklar tam JPEG taşıyabilir.
			frame_data = entropy_payload
		else:
			var state_quality = int(state.get("quality", quality))
			var quality_factor = state_quality if state_quality < 128 else 75
			var state_jpeg_type = int(state.get("jpeg_type", jpeg_type))
			var state_w = int(state.get("img_w", img_w))
			var state_h = int(state.get("img_h", img_h))
			var luma_qt: PackedByteArray = state.get("luma_qt", PackedByteArray())
			var chroma_qt: PackedByteArray = state.get("chroma_qt", PackedByteArray())

			var jpeg_header = _build_jpeg_header(
				state_w if state_w > 0 else width,
				state_h if state_h > 0 else height,
				quality_factor,
				state_jpeg_type,
				luma_qt,
				chroma_qt
			)
			frame_data.append_array(jpeg_header)
			frame_data.append_array(entropy_payload)
			if frame_data.size() < 2 or frame_data[frame_data.size() - 2] != 0xFF or frame_data[frame_data.size() - 1] != 0xD9:
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

func _build_jpeg_header(
	w: int,
	h: int,
	quality: int,
	jpeg_type: int,
	luma_qt: PackedByteArray = PackedByteArray(),
	chroma_qt: PackedByteArray = PackedByteArray()
) -> PackedByteArray:
	var scaled_luma = _scaled_quant_table(_STD_LUMA_QT, quality)
	var scaled_chroma = _scaled_quant_table(_STD_CHROMA_QT, quality)

	var final_luma = _normalize_qt(luma_qt, scaled_luma)
	var final_chroma = _normalize_qt(chroma_qt, scaled_chroma)
	if chroma_qt.size() < 64:
		final_chroma = final_luma

	var hdr = PackedByteArray()

	# SOI
	_append_marker(hdr, 0xD8)

	# APP0 JFIF
	_append_marker(hdr, 0xE0)
	_append_u16(hdr, 16)
	hdr.append_array([0x4A,0x46,0x49,0x46,0x00,0x01,0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00])

	# Quantization tables
	_append_dqt(hdr, 0, final_luma)
	_append_dqt(hdr, 1, final_chroma)

	# Baseline frame header
	_append_sof0(hdr, w, h, jpeg_type)

	# Standard Huffman tables
	_append_dht(hdr, 0, 0, _DHT_DC_LUMA_BITS, _DHT_DC_LUMA_VALS)
	_append_dht(hdr, 1, 0, _DHT_AC_LUMA_BITS, _DHT_AC_LUMA_VALS)
	_append_dht(hdr, 0, 1, _DHT_DC_CHROMA_BITS, _DHT_DC_CHROMA_VALS)
	_append_dht(hdr, 1, 1, _DHT_AC_CHROMA_BITS, _DHT_AC_CHROMA_VALS)

	# Start of Scan
	_append_sos(hdr)

	return hdr

func _append_marker(out: PackedByteArray, marker: int) -> void:
	out.append(0xFF)
	out.append(marker & 0xFF)

func _append_u16(out: PackedByteArray, value: int) -> void:
	out.append((value >> 8) & 0xFF)
	out.append(value & 0xFF)

func _append_dqt(out: PackedByteArray, table_id: int, table_data: PackedByteArray) -> void:
	_append_marker(out, 0xDB)
	_append_u16(out, 67) # 1 byte table-info + 64 quant bytes
	out.append(table_id & 0x0F)
	out.append_array(table_data)

func _append_sof0(out: PackedByteArray, w: int, h: int, jpeg_type: int) -> void:
	var y_sampling = 0x21 # 4:2:2 (type 0)
	if (jpeg_type & 0x3F) == 1:
		y_sampling = 0x22 # 4:2:0 (type 1)

	_append_marker(out, 0xC0)
	_append_u16(out, 17)
	out.append(8) # precision
	_append_u16(out, maxi(1, h))
	_append_u16(out, maxi(1, w))
	out.append(3) # components

	# Y
	out.append(1)
	out.append(y_sampling)
	out.append(0)
	# Cb
	out.append(2)
	out.append(0x11)
	out.append(1)
	# Cr
	out.append(3)
	out.append(0x11)
	out.append(1)

func _append_dht(out: PackedByteArray, table_class: int, table_id: int, bits: Array, values: Array) -> void:
	_append_marker(out, 0xC4)
	_append_u16(out, 1 + 16 + values.size())
	out.append(((table_class & 0x0F) << 4) | (table_id & 0x0F))
	for b in bits:
		out.append(int(b) & 0xFF)
	for v in values:
		out.append(int(v) & 0xFF)

func _append_sos(out: PackedByteArray) -> void:
	_append_marker(out, 0xDA)
	_append_u16(out, 12)
	out.append(3)

	# Y -> DC0/AC0
	out.append(1)
	out.append(0x00)
	# Cb -> DC1/AC1
	out.append(2)
	out.append(0x11)
	# Cr -> DC1/AC1
	out.append(3)
	out.append(0x11)

	out.append(0)
	out.append(63)
	out.append(0)

func _scaled_quant_table(base_qt: Array, quality: int) -> PackedByteArray:
	var q = clampi(quality, 1, 99)
	var scale = (5000.0 / q) if q < 50 else (200.0 - q * 2.0)
	var out = PackedByteArray()
	for v in base_qt:
		var sv = int(clampi(int(int(v) * scale / 100.0), 1, 255))
		out.append(sv)
	return out

func _normalize_qt(src: PackedByteArray, fallback: PackedByteArray) -> PackedByteArray:
	if src.size() < 64:
		return fallback
	var out = PackedByteArray()
	for i in range(64):
		out.append(int(src[i]) & 0xFF)
	return out

func _set_error(msg: String) -> void:
	_last_error = msg
	push_error("[ExtReceiver] " + msg)
	_log("ERR: " + msg)

func _log(msg: String) -> void:
	if show_debug:
		print("[ExtReceiver] " + msg)
