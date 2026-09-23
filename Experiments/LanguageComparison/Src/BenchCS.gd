extends SceneTree
class_name BenchCS
## Compares the GDScript kernel against the same kernel in C#, plus boundary cost. [br]
## Needs a Godot .NET project with the C# kernel; set KERNEL_CS_PATH to its uid first.

#region ENUMS_AND_CONSTANTS

## Trivial calls the boundary cost is averaged over.
const CALLS: int = 1000000

## Uid of the C# kernel script; fill in once the C# port exists in the project.
const KERNEL_CS_PATH: String = "uid://replace_with_kernel_cs_uid"

#endregion

#region LIFECYCLE_AND_METHODS

## Times the kernel in GDScript and C#, then the cost of one trivial call, then quits.
func _init() -> void:
	print("")
	print("=== kernel, whole loop inside the language (one boundary crossing) ===")
	print("    n | GDScript us/search | C# us/search | checksums match")
	print("------+--------------------+--------------+----------------")
	
	for l_entityCount: int in [500, 1000, 3000, 5000]:
		var l_gd: KernelGD = KernelGD.new()
		l_gd.build(l_entityCount)
		var l_start: int = Time.get_ticks_usec()
		var l_gdChecksum: int = l_gd.run()
		var l_gdUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount)
		
		var l_cs: Object = _make_cs()
		l_cs.build(l_entityCount)
		l_cs.run() # Warms the JIT.
		l_cs.build(l_entityCount)
		l_start = Time.get_ticks_usec()
		var l_csChecksum: int = l_cs.run()
		var l_csUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount)
		
		print("%5d | %18.3f | %12.3f | %s" % [l_entityCount, l_gdUs, l_csUs,
			("yes" if l_gdChecksum == l_csChecksum else "NO (%d vs %d)" % [l_gdChecksum, l_csChecksum])])
	
	print("")
	print("=== boundary cost: %d trivial calls from GDScript ===" % CALLS)
	
	var l_noopGd: NoopGD = NoopGD.new()
	var l_sum: int = 0
	var l_callStart: int = Time.get_ticks_usec()
	for l_call: int in CALLS:
		l_sum += l_noopGd.noop(l_call)
	var l_gdNs: float = float(Time.get_ticks_usec() - l_callStart) * 1000.0 / float(CALLS)
	
	var l_noopCs: Object = _make_cs()
	l_noopCs.noop(1)
	l_callStart = Time.get_ticks_usec()
	for l_call: int in CALLS:
		l_sum += l_noopCs.noop(l_call)
	var l_csNs: float = float(Time.get_ticks_usec() - l_callStart) * 1000.0 / float(CALLS)
	
	print("GDScript -> GDScript : %7.1f ns/call" % l_gdNs)
	print("GDScript -> C#       : %7.1f ns/call" % l_csNs)
	
	quit()


## Instantiates the C# kernel; C# classes cannot be named from GDScript directly. [br]
## @return A fresh C# kernel
func _make_cs() -> Object:
	var l_script: Script = load(KERNEL_CS_PATH)
	return l_script.new()

#endregion
