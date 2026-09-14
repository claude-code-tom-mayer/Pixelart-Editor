extends Resource
## Hit side of one entity: what it can be harmed by and what its own hits carry. [br]
## Meant to be shared by every entity of the same archetype.
class_name R_HitProfile

#region PUBLIC_VARIABLES

## Vertical extent the entity occupies as (bottom, top).
@export var yBand: Vector2 = Vector2(0.0, 64.0)

## Bitmask of the hit groups the entity can be harmed by.
@export var hurtGroups: int = 0

## Bitmask of the hit groups the hits of the entity carry.
@export var hitGroups: int = 0

## Bitmask of the hurt groups that end a hit of this entity on the target they match.
@export var stopGroups: int = 0

## Radius over the height, 0 to 100 on both axes; null keeps the radius constant.
@export var radiusCurve: Curve = null

#endregion
