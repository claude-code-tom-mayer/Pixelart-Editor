extends Resource
class_name R_HitData
## Payload one hit carries to the entities it connects with. [br]
## Independent of the hit shape, so the same data can be reused by any hit function.

#region EXPORTS_AND_VARS

## Damage the hit deals to every entity it connects with.
@export var damage: float = 0.0

## Kind of damage, for the receiving side to branch on.
@export var damageType: int = 0

#endregion
