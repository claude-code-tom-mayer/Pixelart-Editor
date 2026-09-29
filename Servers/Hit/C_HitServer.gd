extends RefCounted
class_name C_HitServer
## Constants and orderings of the hit system. [br]
## Hit, hurt and stop groups share their own bitmask space, unrelated to the entity groups.

#region ENUMS_AND_CONSTANTS

## Order a directional rect hit applies its targets in, in the rect's own frame.
enum RECT_ORDER { NONE, FROM_BACK, FROM_FRONT, FROM_LEFT, FROM_RIGHT }

## Order a sector hit applies its targets in, seen from its tip along its direction.
enum SECTOR_ORDER { NONE, RIGHT_TO_LEFT, LEFT_TO_RIGHT }

## Kind of damage a hit deals, for the receiving side to branch on; extend with the game's types.
enum DAMAGE_TYPE { NORMAL }

## Passed as the hit limit to let a hit connect with every valid target.
const UNLIMITED_HITS: int = -1

## Smallest capacity a reused hit buffer grows to, so short hits stop reallocating early.
const BUFFER_MIN_CAPACITY: int = 16

## Samples one radius curve is baked into; a hit reads these, never the Curve itself. [br]
## The last sample sits exactly on the max_domain of the curve, so the count is one above the interval count.
const CURVE_SAMPLE_COUNT: int = 65

#endregion
