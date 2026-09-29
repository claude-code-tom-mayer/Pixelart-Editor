extends Resource
class_name R_TargetingData
## Targeting setup of one entity, handed over once at registration. [br]
## Meant to be shared by every entity of the same archetype.

#region EXPORTS_AND_VARS

## Bitmask of the entity groups the entity may go after.
@export var targetedGroups: int = 0

## How many chunk rings around its own center chunk a search covers.
@export var searchRadiusChunks: int = 4

## A targeter within this many chunk steps makes the entity flee; C_TargetingServer.NEVER_FLEE turns fleeing off.
@export var fleeRadiusChunks: int = 2

## Real distance at which the entity switches from approaching to combat. [br]
## Measured to the silhouette of the target, so its radius is added on top.
@export var combatRange: float = 64.0

## Bitmask of the entity groups the entity goes after before considering the normal ones.
@export var priorityTargetedGroups: int = 0

## Hides the entity from searchers that cannot see invisible ones.
@export var isInvisible: bool = false

## Lets the entity see invisible opponents.
@export var canTargetInvisible: bool = false

## Marks the entity as a focus target, which scores a bonus for searchers.
@export var hasFocus: bool = false

## Lets the entity ignore the focus bonus while scoring.
@export var isIgnoringFocus: bool = false

#endregion
