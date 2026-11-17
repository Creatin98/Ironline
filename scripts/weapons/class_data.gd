class_name ClassData
extends Resource
## One of the preset classes.

@export var class_id: String = "assault"
@export var display_name: String = "Assault Rifle"
@export_multiline var description: String = ""
@export var primary: WeaponData
@export var secondary: WeaponData
@export var grenades: int = 2
@export var flashbangs: int = 1
@export var icon_color: Color = Color(0.9, 0.6, 0.2)
