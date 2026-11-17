class_name Teams
## Team constants and colours shared by gameplay, bots and UI.

enum Team { NONE = 0, RED = 1, BLUE = 2 }

const COLORS := {
	Team.NONE: Color(0.95, 0.75, 0.2),
	Team.RED: Color(0.9, 0.22, 0.18),
	Team.BLUE: Color(0.2, 0.5, 0.95),
}

const NAMES := {
	Team.NONE: "Frei",
	Team.RED: "Rot",
	Team.BLUE: "Blau",
}


static func color_of(team: int) -> Color:
	return COLORS.get(team, COLORS[Team.NONE])


static func name_of(team: int) -> String:
	return NAMES.get(team, "?")


static func opposite(team: int) -> int:
	if team == Team.RED:
		return Team.BLUE
	if team == Team.BLUE:
		return Team.RED
	return Team.NONE
