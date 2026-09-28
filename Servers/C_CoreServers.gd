extends RefCounted
class_name C_CoreServers
## The one sentinel every server's empty slots, chunks, centers, targets, curves and ids resolve to. [br]
## Every "nothing here" case used to be its own -1 constant on a different C_ file; they were all the same value.

#region ENUMS_AND_CONSTANTS

## Stored wherever a slot, chunk, center chain, target, curve slot or entity id points nowhere.
const NO_ID: int = -1

#endregion
