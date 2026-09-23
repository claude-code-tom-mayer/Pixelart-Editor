extends RefCounted
class_name C_FrameBenchmark
## Configuration of the frame benchmark. [br]
## Kept apart from the benchmark itself so every tuning value sits in one place.

#region ENUMS_AND_CONSTANTS

## Entity counts every pass is measured at.
const ENTITY_COUNTS: Array[int] = [300, 500, 750, 1000, 3000, 5000, 10000]

## Frames every pass averages over.
const FRAME_COUNT: int = 10

## Searches one frame is allowed to run, however many entities exist.
const SEARCH_BUDGET: int = 150

## How many chunks in each direction the measured searches cover.
const SEARCH_CHUNKS: int = 4

## Radii handed out in turn, so entities span a realistic mix of chunk counts.
const ENTITY_RADII: Array[float] = [12.0, 24.0, 40.0, 90.0]

## Reach of the single target hit every entity fires once per frame.
const HIT_RADIUS: float = 64.0

## Vertical extent every entity occupies and every hit covers.
const HIT_Y_BAND: Vector2 = Vector2(0.0, 64.0)

## How far a front stands from the map edge, as a share of the map width.
const FRONT_OFFSET: float = 0.35

## How wide a front is spread, as a share of the map width.
const FRONT_SPREAD: float = 0.08

## How far an entity drifts per frame, in world units.
const FRAME_DRIFT: float = 6.0

#endregion
