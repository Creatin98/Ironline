class_name PlayerInputState
extends RefCounted
## Abstract input a Player consumes each physics frame. Filled either by a
## HumanController (keyboard/mouse) or a BotController (AI). This is what makes
## humans and bots share the exact same movement and weapon code.

var move: Vector2 = Vector2.ZERO        # x = rechts, y = vorwaerts (-1..1)
var look_delta: Vector2 = Vector2.ZERO  # Radiant, bereits mit Sensitivitaet skaliert
var sprint: bool = false
var crouch: bool = false
var aim: bool = false
var fire_held: bool = false
var fire_pressed: bool = false
var jump_pressed: bool = false
var reload_pressed: bool = false
var grenade_pressed: bool = false
var switch_pressed: bool = false
var select_primary: bool = false
var select_secondary: bool = false


## Call after the frame was processed so one-shot actions do not repeat.
func clear_one_shot() -> void:
	look_delta = Vector2.ZERO
	fire_pressed = false
	jump_pressed = false
	reload_pressed = false
	grenade_pressed = false
	switch_pressed = false
	select_primary = false
	select_secondary = false


func clear_all() -> void:
	clear_one_shot()
	move = Vector2.ZERO
	sprint = false
	crouch = false
	aim = false
	fire_held = false
