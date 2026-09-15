extends Resource
## Targeting setup of one entity, handed over once at registration. [br]
## Meant to be shared by every entity of the same archetype.
class_name R_TargetingData

#region PUBLIC_VARIABLES

## Bitmask of the groups the entity may go after.
@export var targetedGroups: int = 0

## How many chunks in each direction a search covers.
@export var searchChunks: int = 4

## A targeter closer than this many chunks makes the entity flee.
@export var fleeChunks: int = 2

## Real distance at which the entity switches from approaching to combat. [br]
## Measured to the silhouette of the target, so its radius is added on top.
@export var hitRange: float = 64.0

## Bitmask of the groups the entity goes after before considering the normal ones.
@export var priorityTargetedGroups: int = 0

## Hides the entity from searchers that cannot see invisible ones.
@export var invisible: bool = false

## Lets the entity see invisible enemies.
@export var targetsInvisible: bool = false

## Marks the entity as a focus target, which scores a bonus for searchers.
@export var hasFocus: bool = false

## Lets the entity ignore the focus bonus while scoring.
@export var ignoresFocus: bool = false

#endregion
