extends RefCounted
class_name C_TeamBucketCompare
## Configuration of the team bucket comparison. [br]
## Both variants read the same values, so they are measured against the same world.

#region ENUMS_AND_CONSTANTS

## Entity counts every variant is measured at.
const ENTITY_COUNTS: Array[int] = [500, 1000, 3000, 5000]

## How many chunks in each direction every search covers.
const SEARCH_CHUNKS: int = 4

## Frames every measurement averages over.
const FRAME_COUNT: int = 10

## Radii handed out in turn, so entities span a realistic mix of chunk counts.
const ENTITY_RADII: Array[float] = [12.0, 24.0, 40.0, 90.0]

## How far a front stands from the map edge, as a share of the map width.
const FRONT_OFFSET: float = 0.35

## How wide a front is spread, as a share of the map width.
const FRONT_SPREAD: float = 0.08

#endregion
