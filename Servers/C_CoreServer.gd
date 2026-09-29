extends RefCounted
class_name C_CoreServer
## Constants every server shares: the teams and the one "points nowhere" sentinel. [br]
## See docs/TERMS.html for every term the servers use.

#region ENUMS_AND_CONSTANTS

## Teams an entity can fight for; the values index every per team container.
enum TEAM { ATTACKER, DEFENDER }

## Stored wherever an entity id, slot, chunk, target or curve id points nowhere.
const NO_ID: int = -1

## Number of teams; size of every per team container. Derived once from TEAM.
static var TEAM_COUNT: int

#endregion

#region LIFECYCLE_AND_METHODS

## Derives the team count once, on class load.
static func _static_init() -> void:
	TEAM_COUNT = TEAM.size()

#endregion
