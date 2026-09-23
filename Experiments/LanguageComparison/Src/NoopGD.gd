extends RefCounted
class_name NoopGD
## Trivial GDScript method, the baseline of the boundary cost measurement.

#region LIFECYCLE_AND_METHODS

## Returns its argument unchanged, so a call costs nothing but the call itself. [br]
## @param p_value The value to hand back [br]
## @return The same value
func noop(p_value: int) -> int:
	return p_value

#endregion
