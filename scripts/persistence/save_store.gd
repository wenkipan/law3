extends RefCounted

const MAGIC := "LAW3SAVE"
const MAX_BYTES := 64 * 1024 * 1024
const SLOT_COUNT := 6
const DIRECTORY := "user://saves"

static func slot_path(slot: int, directory := DIRECTORY) -> String:
	# Keep the original default save available as the first menu slot.
	return directory.path_join("colony.law3" if slot == 0 else "colony-%d.law3" % (slot + 1))

static func slots(directory := DIRECTORY) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for slot in SLOT_COUNT:
		var path := slot_path(slot, directory)
		entries.append({"exists": FileAccess.file_exists(path), "backup": FileAccess.file_exists(path + ".bak"),
			"modified": FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0})
	return entries

static func failure(message: String, code := "invalid") -> Dictionary:
	return {"ok": false, "error": message, "code": code}

static func checksum(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish()

static func read_save(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return failure("Cannot open save: " + error_string(FileAccess.get_open_error()), "open")
	var size := file.get_length()
	if size < 48 or size > MAX_BYTES: return failure("Invalid save file size.")
	if file.get_buffer(8).get_string_from_ascii() != MAGIC: return failure("Not a Bread and Ore save.")
	var length := file.get_64()
	var expected := file.get_buffer(32)
	if length != size - 48: return failure("Save is incomplete.")
	var data := file.get_buffer(length)
	if checksum(data) != expected: return failure("Save checksum failed; the previous save is available as .bak.", "checksum")
	return {"ok": true, "data": data}

static func write_save(path: String, data: PackedByteArray) -> Dictionary:
	if data.is_empty() or data.size() > MAX_BYTES - 48: return failure("Snapshot is empty or too large.")
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute): return failure("Save destination is a directory.", "write")
	var directory := absolute.get_base_dir()
	var result := DirAccess.make_dir_recursive_absolute(directory)
	if result != OK: return failure("Cannot create save directory: " + error_string(result), "write")
	var suffix := ".tmp.%d.%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temporary := absolute + suffix
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return failure("Cannot write save: " + error_string(FileAccess.get_open_error()), "write")
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_64(data.size())
	file.store_buffer(checksum(data))
	file.store_buffer(data)
	file.flush()
	result = file.get_error()
	file.close()
	if result != OK:
		DirAccess.remove_absolute(temporary)
		return failure("Could not finish writing save: " + error_string(result), "write")
	var verified := read_save(temporary)
	if not verified.ok:
		DirAccess.remove_absolute(temporary)
		return verified
	# Never replace a good backup with a damaged primary, and never remove the
	# primary before the completed temporary file can replace it atomically.
	if FileAccess.file_exists(absolute) and read_save(absolute).ok:
		var backup_temp := absolute + ".bak" + suffix
		result = DirAccess.copy_absolute(absolute, backup_temp)
		if result == OK: result = DirAccess.rename_absolute(backup_temp, absolute + ".bak")
		if result != OK:
			DirAccess.remove_absolute(temporary)
			DirAccess.remove_absolute(backup_temp)
			return failure("Could not preserve previous save: " + error_string(result), "write")
	result = DirAccess.rename_absolute(temporary, absolute)
	if result != OK:
		DirAccess.remove_absolute(temporary)
		return failure("Could not replace save: " + error_string(result), "write")
	return {"ok": true, "path": absolute}
