extends Resource
## Everything one archetype of entity needs to exist, across all servers. [br]
## The api server splits it up and hands each server only its own part.
class_name R_EntityData

#region PUBLIC_VARIABLES

## Effect radius; decides in how many chunks the entity stands.
@export var radius: float = 24.0

## Bitmask of the groups the entity belongs to.
@export var groups: int = 0

## Band, groups and radius profile the hit server needs.
@export var hitProfile: R_HitProfile = null

## Groups, ranges and flags the targeting server needs.
@export var targetingData: R_TargetingData = null

#endregion
