class_name Player
extends CharacterBody2D

enum MoveStates {
	Walk, 
	Crawl, 
	Sprint, 
	Jump, 
	Climb,
}

const JUMP_VELOCITY: float = -225.0

var speed: float = 90.0
var sprint_speed: float = 300.0
var crouch_speed: float = 40.0
var climb_speed: float = 50.0

var gravity: int = ProjectSettings.get_setting("physics/2d/default_gravity")

var current_move_state: MoveStates = MoveStates.Walk

var is_touching_ladder: bool = false : 
	set(new_value):
		is_touching_ladder = new_value
		print("CHANGED TO: ", is_touching_ladder)

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var jump_buffer: Timer = $JumpBuffer
@onready var coyote_timer: Timer = $CoyoteTime
@onready var headspace_detector: RayCast2D = $HeadSpaceDetector
@onready var jump_detector: RayCast2D = $JumpDetector


func _ready() -> void:
	anim_player.play("RESET")
	SceneManager.paused.connect(_on_pause)
	SaveManager.about_to_save.connect(_save_game_data)
	
	SceneManager.pause("player", true)  # stay paused until fully loaded; parent handles unpause


func _on_pause(layer: String) -> void:
	if layer in ["player", "game", "all"]:
		anim_player.play("crawl idle" if headspace_detector.is_colliding() else "idle")
		velocity.x = 0


func _save_game_data(reason: SaveManager.SaveReason) -> void:
	SaveManager.save_data.player_data = SaveManager.save_data.get("player_data", SaveManager.DEFAULT_SAVE_DATA.player_data)
	SaveManager.save_data.player_data.scene_position = global_position
	
	if owner.name == "World":
		SaveManager.save_data.player_data.world_position = global_position


func _physics_process(delta: float) -> void:
	if SceneManager.is_paused("player", ["game"]):
		return
	
#	Falling
	if current_move_state != MoveStates.Climb and not is_on_floor():
		velocity.y += gravity * delta

#	Jumping
	if Input.is_action_just_pressed("jump"):
		if not is_touching_ladder and not headspace_detector.is_colliding() and not jump_detector.is_colliding():
			if is_on_floor() or not coyote_timer.is_stopped():
				velocity.y = JUMP_VELOCITY
				current_move_state = MoveStates.Jump
				coyote_timer.stop()
			else:
				jump_buffer.start()
	
#	Crawl Check
	if headspace_detector.is_colliding():
		current_move_state = MoveStates.Crawl

	handle_movement(delta)
	
	handle_animations()


func handle_movement(delta: float) -> void:
	if Input.is_action_pressed("jump") and is_touching_ladder:
		current_move_state = MoveStates.Climb
		velocity.y = -climb_speed
	elif Input.is_action_pressed("crawl") and current_move_state != MoveStates.Jump:
		if current_move_state == MoveStates.Climb:
			velocity.y = climb_speed
		elif is_touching_ladder:
			current_move_state = MoveStates.Climb
		else:
			current_move_state = MoveStates.Crawl
	elif Input.is_action_pressed("sprint") and current_move_state != MoveStates.Jump:
		current_move_state = MoveStates.Sprint
	elif current_move_state == MoveStates.Climb:
		velocity.y = 0
	elif current_move_state != MoveStates.Jump:
		if headspace_detector.is_colliding() and current_move_state == MoveStates.Crawl:
			current_move_state = MoveStates.Crawl
		else:
			current_move_state = MoveStates.Walk
	
	var direction: int = Input.get_axis("walk_left", "walk_right")
	if direction:
		if current_move_state == MoveStates.Sprint:
			velocity.x = direction * sprint_speed
		elif current_move_state == MoveStates.Crawl:
			velocity.x = direction * crouch_speed
		elif current_move_state == MoveStates.Climb:
			velocity.x = direction * climb_speed
		else:
			velocity.x = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
	
	move_and_slide()


func handle_animations() -> void:
	if velocity.x > 0:
		sprite.flip_h = false
	elif velocity.x < 0:
		sprite.flip_h = true
	if velocity.y == 0 or current_move_state == MoveStates.Crawl:
		if current_move_state == MoveStates.Jump:
			current_move_state = MoveStates.Walk
		match current_move_state:
			MoveStates.Walk:
				if velocity.x != 0:
					anim_player.play("walk")
				else:
					anim_player.play("idle")
			MoveStates.Sprint:
				if velocity.x != 0:
					anim_player.play("sprint")
				else:
					anim_player.play("idle")
			MoveStates.Crawl:
				if velocity.x != 0:
					anim_player.play("crawl")
				else:
					anim_player.play("crawl idle")
			MoveStates.Climb:
				anim_player.play("climb idle")
	elif current_move_state == MoveStates.Climb:
		anim_player.play("climb")
	else:
		anim_player.play("jump")


func _on_land_detector_body_entered(body: Node2D) -> void:
	if not jump_buffer.is_stopped():
		if not jump_detector.is_colliding():
			velocity.y = JUMP_VELOCITY
		jump_buffer.stop()


func _on_land_detector_body_exited(body: Node2D) -> void:
	if velocity.y < 0:
		return
	if coyote_timer and coyote_timer.is_inside_tree():
		coyote_timer.start()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PAUSED:
			if headspace_detector.is_colliding():
				anim_player.play("crawl idle")
			else:
				anim_player.play("idle")
