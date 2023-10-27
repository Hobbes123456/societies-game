extends Node

signal _background_load_finished()

signal deactivate(node: Node)
signal activate(node: Node)
signal scenes_ready()
signal paused(layer: String)
signal unpaused(layer: String)

@export var scenes_to_cache: Array[String]
@export var load_cached_scenes_on_start: bool = false
@export_file("*.tscn") var start_scene: String = ""
@export var pause_layers: Dictionary = {
	"entities": false, 
	"interaction": false, 
	"all": false
}

var scenes_loaded: Dictionary = {}  # keys are scene paths, values are filesystem paths

var progress: Array = []
var scene_load_status: ResourceLoader.ThreadLoadStatus = 0

var previous_frame_progress: int = -1

var currently_loading_scene: String = ""
var loaded_scene

var active_scene: String = ""
var active_scene_node: Node

var are_scenes_ready: bool = false

var scene_history: Array = []

var persistent_information: Dictionary = {}

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var progress_bar: ProgressBar = $Visuals/ColorRect/CenterContainer/ProgressBar
@onready var visuals: CanvasLayer = $Visuals
@onready var scenes: Node = $Scenes


func _ready() -> void:
	if str(get_tree().current_scene.get_path()) != "/root/blank":
		return
	
	scenes_ready.connect(
		func():
			are_scenes_ready = true
	)
	
	$Visuals/ColorRect.global_position.x = 0
	
	if load_cached_scenes_on_start:
		for scene in scenes_to_cache:
			await _load_scene(scene)
	
	await change_scene(start_scene, false, true, scenes_ready)


func change_scene(filename: String, slide_in: bool = true, slide_out: bool = true, emit_after_loading: Variant = null) -> void:
	visuals.show()
	if len(scenes_loaded) > 0 and slide_in:
		animation_player.play("slide_in")
		await animation_player.animation_finished
	else:
		await get_tree().create_timer(0.2).timeout
	
	if filename in scenes_to_cache:
		progress_bar.show()
	
	if filename not in scenes_loaded.values():
		pause_layers[filename] = false
		await _load_scene(filename)
	else:
		_activate_scene(scenes_loaded.keys()[scenes_loaded.values().find(filename)])
	
	if typeof(emit_after_loading) == TYPE_SIGNAL:
		emit_after_loading.emit()
	
	scene_history.append(filename)
	
	progress_bar.hide()
	if slide_out:
		animation_player.play("slide_out")
		await animation_player.animation_finished


func is_paused(layer: String, others: Array = []) -> bool:
	if others != []:
		for l in others:
			if pause_layers.has(l) and pause_layers[l]:
				return true
	return (pause_layers.has(layer) and pause_layers[layer]) or pause_layers["all"]


func pause(layer: String, is_paused: bool) -> void:
	if pause_layers.has(layer):
		pause_layers[layer] = is_paused
	
	if is_paused:
		paused.emit(layer)
	else:
		unpaused.emit(layer)


func add_pause_layer(layer_name: String, default: bool = false) -> void:
	pause_layers[layer_name] = default


func get_persistent_information(key: String) -> Variant:
	return persistent_information.get(key, null)


func set_persistent_information(key: String, value: Variant) -> void:
	persistent_information[key] = value


func _activate_scene(path: String) -> void:
	if not has_node(path):
		return
	
	for other_scene in scenes_loaded.keys():
		if str(other_scene) == path:
			continue
		_deactivate_scene(str(other_scene))
	
	active_scene = path
	active_scene_node = get_node(path)
	activate.emit(get_node(path))
	get_node(path).show()


func _deactivate_scene(path: String) -> void:
	if not has_node(path):
		return
	deactivate.emit(get_node(path))
	if active_scene == path:
		active_scene = ""
	if active_scene_node == get_node(path):
		active_scene_node = null
	if path in scenes_loaded.keys() and scenes_loaded[path] not in scenes_to_cache:
		scenes_loaded.erase(path)
		get_node(path).queue_free()
	else:
		get_node(path).hide()


func _load_scene(scene_path: String) -> void:
	if (not scene_path.begins_with("res://")) or (not scene_path.ends_with(".tscn")):
		return
	ResourceLoader.load_threaded_request(scene_path)
	currently_loading_scene = scene_path
	set_process(true)
	await self._background_load_finished
	currently_loading_scene = ""
	
	var scene = loaded_scene.instantiate()
	
	scenes.add_child(scene)
	
	_activate_scene(get_path_to(scene))
	
	scenes_loaded[str(get_path_to(scene))] = scene_path


func _process(delta: float) -> void:
	if currently_loading_scene == "":
		return
	
	scene_load_status = ResourceLoader.load_threaded_get_status(currently_loading_scene, progress)
	
	if previous_frame_progress != progress[0] * 100:
		progress_bar.value = progress[0] * 100
	previous_frame_progress = progress[0] * 100
	
	match scene_load_status:
		ResourceLoader.THREAD_LOAD_LOADED:
			loaded_scene = ResourceLoader.load_threaded_get(currently_loading_scene)
			_background_load_finished.emit()
			set_process(false)
		ResourceLoader.THREAD_LOAD_FAILED:
			progress_bar.hide()
			set_process(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Engine.max_fps = 8
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = 0