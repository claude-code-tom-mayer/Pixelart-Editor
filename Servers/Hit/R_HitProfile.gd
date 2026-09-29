extends Resource
class_name R_HitProfile
## Hit side of one entity: what it can be harmed by and what its own hits carry. [br]
## Meant to be shared by every entity of the same archetype.

#region EXPORTS_AND_VARS

## Vertical extent the entity occupies above the ground, as (bottom, top).
@export var heightBand: Vector2 = Vector2(0.0, 64.0)

## Bitmask of the hit groups the entity can be harmed by.
@export var hurtGroups: int = 0

## Bitmask of the hit groups the hits of the entity carry.
@export var hitGroups: int = 0

## Bitmask of the hurt groups that end an ordered hit of this entity on the target they match.
@export var stopGroups: int = 0

## Radius over the height: the domain spans the height band, max_value is the full radius. [br]
## Any domain and value range works; null keeps the radius constant.
@export var radiusCurve: Curve = null

#endregion
