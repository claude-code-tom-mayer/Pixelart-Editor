extends Resource
class_name R_EntityData
## Everything one archetype of entity needs to exist, across all servers. [br]
## The api server splits it up and hands each server only its own part.

#region EXPORTS_AND_VARS

## Effect radius; decides in how many chunks the entity stands.
@export var radius: float = 24.0

## Bitmask of the groups the entity belongs to.
@export var groups: int = 0

## Band, groups and radius profile the hit server needs. [br]
## Leaving it empty registers the entity on the default profile and reports it.
@export var hitProfile: R_HitProfile = null

## Groups, ranges and flags the targeting server needs. [br]
## Leaving it empty registers the entity on the default setup and reports it.
@export var targetingData: R_TargetingData = null

#endregion
