extends RefCounted
## Constants and orderings of the hit system. [br]
## Hit groups are their own bitmask space, unrelated to the chunking groups.
class_name C_HitServer

#region CONFIGURATION

## Edge of a directional rect an ordered hit starts from, in the rect's own frame.
enum RECT_EDGE { BACK, FRONT, LEFT, RIGHT }

## Passed as the hit limit to let a hit connect with every valid target.
const UNLIMITED_HITS: int = -1

## Passed as the preferred target when the hit has no target to check first.
const NO_PREFERRED_TARGET: int = -1

## Stored as the curve slot of an entity whose radius is constant over its whole height.
const NO_CURVE: int = -1

## Upper end of both curve axes; radius curves run from 0 to 100 in x and y.
const CURVE_PERCENT_MAX: float = 100.0

## Smallest capacity a reused hit buffer grows to, so short hits stop reallocating early.
const BUFFER_MIN_CAPACITY: int = 16

## Samples one radius curve is baked into; a hit reads these, never the Curve itself. [br]
## The last sample sits exactly on CURVE_PERCENT_MAX, so the count is one above the interval count.
const CURVE_SAMPLE_COUNT: int = 65

#endregion
