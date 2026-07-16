extends SceneTree

## Runs from an empty temporary Godot project and validates the exported PCK's
## scoped virtual resource tree. This is stronger than grepping binary strings:
## every pack entry must belong to Project Breakwater's allowed files, source
## directories, or Godot-generated import/export directories.

const ALLOWED_SOURCE_DIRS := [
	"src/audio/",
	"src/autoload/",
	"src/game/",
	"src/gameplay/",
	"src/ui/",
	"src/vfx/",
	"src/world/",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("verify_export_pack.gd requires an absolute PCK path")
		quit(2)
		return
	if not ProjectSettings.load_resource_pack(args[0], true):
		push_error("Could not load exported resource pack: %s" % args[0])
		quit(2)
		return
	var files: PackedStringArray = []
	_collect_files("res://", files)
	var rejected: PackedStringArray = []
	for file_path in files:
		var relative := file_path.trim_prefix("res://")
		if not _is_allowed(relative):
			rejected.append(relative)
	if not rejected.is_empty():
		for path in rejected:
			push_error("Disallowed export resource: %s" % path)
		quit(1)
		return
	print("PACK_MANIFEST_OK files=%d" % files.size())
	quit(0)


func _collect_files(directory_path: String, output: PackedStringArray) -> void:
	for file_name in DirAccess.get_files_at(directory_path):
		output.append(directory_path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(directory_path):
		_collect_files(directory_path.path_join(directory_name), output)


func _is_allowed(relative_path: String) -> bool:
	if relative_path == "project.godot" \
		or relative_path == "project.binary" \
		or relative_path == "default_bus_layout.tres" \
		or relative_path == "default_bus_layout.tres.remap" \
		or relative_path == "assets/icon.svg" \
		or relative_path == "assets/icon.svg.import" \
		or relative_path == "assets/ui/breakwater_station_menu.png" \
		or relative_path == "assets/ui/breakwater_station_menu.png.import" \
		or relative_path == "scenes/main.tscn" \
		or relative_path == "scenes/main.tscn.remap" \
		or relative_path == "src/main.gd" \
		or relative_path == "src/main.gd.remap" \
		or relative_path == "src/main.gdc" \
		or relative_path == ".godot/global_script_class_cache.cfg" \
		or relative_path == ".godot/uid_cache.bin":
		return true
	if relative_path.begins_with(".godot/exported/") \
		or relative_path.begins_with(".godot/imported/"):
		return true
	for allowed_directory in ALLOWED_SOURCE_DIRS:
		if relative_path.begins_with(allowed_directory):
			return relative_path.get_extension() in ["gd", "gdc", "remap"]
	return false
