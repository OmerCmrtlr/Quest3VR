extends TextureRect
## GStreamerReceiver veya GStreamerCamera'dan gelen texture'ı ekrana yansıtır.

@export var receiver_path: NodePath

var _source: Node = null
var _source_type := ""
var _first_frame_logged := false

func _ready() -> void:
	_find_source()

func _find_source() -> void:
	if receiver_path.is_empty():
		push_error("[ReceiverDisplay] receiver_path boş")
		return

	_source = get_node_or_null(receiver_path)
	if _source == null:
		push_error("[ReceiverDisplay] Kaynak bulunamadı: %s" % receiver_path)
		return

	if _source.has_method("is_receiving"):
		_source_type = "receiver"
	elif _source.has_method("is_capturing"):
		_source_type = "camera"
	else:
		_source_type = "unknown"

func _is_source_active() -> bool:
	if _source == null:
		return false

	if _source_type == "receiver" and _source.has_method("is_receiving"):
		return _source.call("is_receiving")

	if _source_type == "camera" and _source.has_method("is_capturing"):
		return _source.call("is_capturing")

	if _source.has_method("is_receiving"):
		return _source.call("is_receiving")

	if _source.has_method("is_capturing"):
		return _source.call("is_capturing")

	return false

func _process(_delta: float) -> void:
	if _source == null:
		_find_source()
		return

	if not _is_source_active():
		return

	if not _source.has_method("get_texture"):
		return

	var tex := _source.call("get_texture")
	if tex != null:
		texture = tex
		if not _first_frame_logged:
			print("[ReceiverDisplay] İlk texture alındı.")
			_first_frame_logged = true
