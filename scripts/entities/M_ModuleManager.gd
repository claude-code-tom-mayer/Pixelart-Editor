extends RefCounted
## Holds and drives the modules of one entity. [br]
## Receives every hit that connects with its entity and records it for tests.
class_name M_ModuleManager

#region PUBLIC_VARIABLES

## Data of the last hit this entity took; null while it was never hit.
var lastHitData: R_HitData = null

## Number of hits this entity took.
var hitCount: int = 0

#endregion

#region PUBLIC_METHODS

## Applies one hit to the entity and records it. [br]
## @param p_hitData The payload of the hit that connected
func hit(p_hitData: R_HitData) -> void:
	lastHitData = p_hitData
	hitCount += 1

#endregion
