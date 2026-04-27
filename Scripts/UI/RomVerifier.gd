class_name ROMVerifier
extends Node

const VALID_HASHES := [
	"6a54024d5abe423b53338c9b418e0c2ffd86fed529556348e52ffca6f9b53b1a",
	"c9b34443c0414f3b91ef496d8cfee9fdd72405d673985afa11fb56732c96152b"
]
const ROM_FILE_FILTER := "*.nes,*.nez,*.fds,*.qd,*.unf,*.unif,*.nsf,*.nsfe;ROM image files"
const EXTENSION_ERROR_TEXT := "ERROR VERIFYING ROM!\n\nARE YOU SURE THIS IS A ROM IMAGE FILE?"
const NATIVE_PICKER_ERROR_TEXT := "NATIVE FILE PICKER UNAVAILABLE!\n\nTHIS BUILD NEEDS A PLATFORM FILE PICKER BRIDGE."

var args: PackedStringArray
var rom_arg: String = ""
var accepting_rom_input := false
var native_file_dialog_open := false

@onready var select_rom: Button = %SelectRom

func _ready() -> void:
	args = OS.get_cmdline_args()
	Global.get_node("GameHUD").hide()

	# Try command line ROMs first
	for i in range(args.size()):
		match args[i]:
			"-rom":
				if i + 1 < args.size():
					rom_arg = args[i + 1].replace("\\", "/")
					print("ROM argument found: ", rom_arg)
	if rom_arg != "" and handle_rom(rom_arg):
		return
	
	# Fallback: local ROM
	var local_rom := find_local_rom()
	if local_rom != "" and handle_rom(local_rom):
		return
	
	# Otherwise wait for dropped/selected files
	# SkyanUltra: Added button to select files for convenience
	get_window().files_dropped.connect(on_file_dropped)
	select_rom.pressed.connect(file_prompt_open)
	accepting_rom_input = true
	await get_tree().physics_frame

	# Window setup
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

func _unhandled_input(event: InputEvent) -> void:
	if not can_open_file_prompt():
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		file_prompt_open()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			file_prompt_open()

func find_local_rom() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var dir := DirAccess.open(exe_dir)
	if not dir:
		return ""
	for file_name in dir.get_files():
		if file_name.to_lower().ends_with(".nes"):
			return exe_dir.path_join(file_name)
	return ""
  
func on_file_dropped(files: PackedStringArray) -> void:
	for file in files:
		if handle_rom(file):
			return
	error()

func can_open_file_prompt() -> bool:
	return (
		accepting_rom_input
		and not native_file_dialog_open
		and is_instance_valid(select_rom)
		and not select_rom.disabled
	)
	
func file_prompt_open() -> void:
	if not can_open_file_prompt():
		return
	select_rom.disabled = true
	if open_native_file_prompt():
		return
	native_picker_error()
	file_prompt_closed()

func open_native_file_prompt() -> bool:
	native_file_dialog_open = true
	var current_directory := OS.get_executable_path().get_base_dir()
	var result := ERR_UNAVAILABLE

	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE_EXTRA):
		result = DisplayServer.file_dialog_with_options_show(
			"SELECT A VALID ROM",
			current_directory,
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray([ROM_FILE_FILTER]),
			[],
			on_native_file_dialog_with_options_closed,
			get_window().get_window_id()
		)
	elif DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		result = DisplayServer.file_dialog_show(
			"SELECT A VALID ROM",
			current_directory,
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray([ROM_FILE_FILTER]),
			on_native_file_dialog_closed,
			get_window().get_window_id()
		)

	if result != OK:
		native_file_dialog_open = false
		return false
	return true

func on_native_file_dialog_closed(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
	native_file_dialog_open = false
	if not status or selected_paths.is_empty():
		file_prompt_closed()
		return
	on_file_dropped(selected_paths)

func on_native_file_dialog_with_options_closed(
	status: bool,
	selected_paths: PackedStringArray,
	selected_filter_index: int,
	_selected_options: Dictionary
) -> void:
	on_native_file_dialog_closed(status, selected_paths, selected_filter_index)
	
func file_prompt_closed() -> void:
	native_file_dialog_open = false
	if is_instance_valid(select_rom):
		select_rom.disabled = false

func handle_rom(path: String) -> bool:
	file_prompt_closed()
	if path.get_extension() in ["zip", "7z", "rar", "tar", "gz", "gzip", "bz2"]:
		zip_error()
		return false
	if not is_valid_rom(path):
		if path.get_extension() in ["nes", "nez", "fds", "qd", "unf", "unif", "nsf", "nsfe"]:
			error()
		else: extension_error()
		return false
	Global.rom_path = path
	accepting_rom_input = false
	copy_rom(path)
	verified()
	return true

func copy_rom(file_path: String) -> void:
	DirAccess.copy_absolute(file_path, Global.ROM_PATH)

static func get_hash(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""
	var file_bytes := file.get_buffer(40976)
	var data := file_bytes.slice(16)
	return Marshalls.raw_to_base64(data).sha256_text()

static func is_valid_rom(rom_path := "") -> bool:
	return get_hash(rom_path) in VALID_HASHES


func error() -> void:
	%Error.show()
	%ZipError.hide()
	%ExtensionError.hide()
	$ErrorSFX.play()

func zip_error() -> void:
	%ZipError.show()
	%Error.hide()
	%ExtensionError.hide()
	$ErrorSFX.play()
	
func extension_error() -> void:
	%ExtensionError.text = EXTENSION_ERROR_TEXT
	%ExtensionError.show()
	%Error.hide()
	%ZipError.hide()
	$ErrorSFX.play()

func native_picker_error() -> void:
	push_error("Native file picker is unavailable in this Godot runtime/display server. This build needs a platform-native picker bridge.")
	%ExtensionError.text = NATIVE_PICKER_ERROR_TEXT
	%ExtensionError.show()
	%Error.hide()
	%ZipError.hide()
	$ErrorSFX.play()

func verified() -> void:
	$BGM.queue_free()
	%DefaultText.queue_free()
	%SuccessMSG.show()
	$SuccessSFX.play()
	await get_tree().create_timer(3, false).timeout
	
	var target_scene := "res://Scenes/Levels/TitleScreen.tscn"
	if not Global.rom_assets_exist:
		target_scene = "res://Scenes/Levels/RomResourceGenerator.tscn"
	Global.transition_to_scene(target_scene)

func _exit_tree() -> void:
	Global.get_node("GameHUD").show()

func create_file_pointer(file_path: String) -> void:
	var pointer := FileAccess.open(Global.ROM_POINTER_PATH, FileAccess.WRITE)
	if pointer:
		pointer.store_string(file_path)
		pointer.close()
