extends Node
class_name EndToEndTest
## Drives entities through the chunking, hit and targeting autoloads the way the game does. [br]
## Run it headless through its scene: godot --headless res://Tests/EndToEndTest.tscn

#region EXPORTS_AND_VARS

## Module manager that fires a hit of its own while it takes one, like thorns would. [br]
## Its counter hit lands on two targets, which overwrote the pending dispatches before the snapshot fix.
class ReentrantModuleManager extends M_ModuleManager:
	## The entity this module manager belongs to; its own hits come from here.
	var ownerId: int = C_CoreServer.NO_ID

	## Payload of the hit this module manager fires back.
	var counterHitData: R_HitData = null

	## Takes the hit, then fires a counter hit around its owner once. [br]
	## @param p_hitData The payload of the hit that connected
	func hit(p_hitData: R_HitData) -> void:
		super.hit(p_hitData)

		if (hitCount == 1):
			G_HitServer.hit_circle(ownerId, A_CoreServer._entityPosition[ownerId], 300.0, Vector2(0.0, 64.0),
				C_HitServer.UNLIMITED_HITS, C_CoreServer.NO_ID, counterHitData, false)

## Module manager that announces another entity for removal while it takes a hit, like a death explosion would.
class RemovingModuleManager extends M_ModuleManager:
	## The entity announced for removal on the first hit.
	var victimId: int = C_CoreServer.NO_ID

	## Takes the hit, then announces the victim for removal once. [br]
	## @param p_hitData The payload of the hit that connected
	func hit(p_hitData: R_HitData) -> void:
		super.hit(p_hitData)

		if (hitCount == 1):
			A_CoreServer.pre_unregister(victimId)

## Every id the running check registered; removed again before the next check starts.
var _liveIds: PackedInt32Array = PackedInt32Array()

## Hit groups every armed entity carries and can be harmed by.
var _hitProfile: R_HitProfile = null

## Targeting setup every armed entity shares.
var _targetingData: R_TargetingData = null

## Payload of every hit the checks fire.
var _hitData: R_HitData = null

## Number of expectations that did not hold.
var _failureCount: int = 0

## Number of expectations that were checked.
var _checkCount: int = 0

#endregion

#region LIFECYCLE_AND_METHODS

## Runs every check, prints a summary and quits with a non zero code on failure. [br]
## Runs as the main scene, so the server autoloads are already loaded.
func _ready() -> void:
	_hitProfile = R_HitProfile.new()
	_hitProfile.hurtGroups = 0b1
	_hitProfile.hitGroups = 0b1

	_targetingData = R_TargetingData.new()
	_targetingData.targetedGroups = 0b1

	_hitData = R_HitData.new()
	_hitData.damage = 5.0

	_check_shared_static_data()
	_check_targeting_flow()
	_check_hits()
	_check_removal_lifecycle()
	_check_id_reuse()
	_check_inert_registration()
	_check_targeter_chain()
	_check_ordered_hits()
	_check_reentrant_hit()
	_check_removal_during_dispatch()

	print("")
	print("%d of %d checks passed" % [_checkCount - _failureCount, _checkCount])
	get_tree().quit(1 if _failureCount > 0 else 0)


## Removes every entity of the previous check, so each check starts on empty servers.
func _clear_world() -> void:
	for l_id: int in _liveIds:
		A_CoreServer.unregister(l_id)

	A_CoreServer.release_removed_ids()
	_liveIds.clear()


## Registers one fully armed entity on every server at once, the way an entity does on spawn. [br]
## @param p_position Start position [br]
## @param p_team Team, a C_CoreServer.TEAM value [br]
## @param p_moduleManager Module manager that receives its hits [br]
## @return The id the entity uses on every server
func _spawn(p_position: Vector2, p_team: C_CoreServer.TEAM, p_moduleManager: M_ModuleManager) -> int:
	var l_id: int = A_CoreServer.register(p_position, 24.0, p_team, 0b1, p_moduleManager, _hitProfile, _targetingData)
	_liveIds.append(l_id)

	return l_id


## Registers one entity without hit profile and targeting data, so it carries no hit or targeting groups. [br]
## It still stands on the chunk index, so it can be targeted: the entity is inert. [br]
## @param p_position Start position [br]
## @param p_team Team, a C_CoreServer.TEAM value [br]
## @return The id the entity uses on every server
func _spawn_inert(p_position: Vector2, p_team: C_CoreServer.TEAM) -> int:
	var l_id: int = A_CoreServer.register(p_position, 24.0, p_team, 0b1, null, null, null)
	_liveIds.append(l_id)

	return l_id


## Fires a single target circle hit from an entity at its own position. [br]
## @param p_emitterId The entity that hits [br]
## @param p_origin Where the hit is centered [br]
## @return How many targets the hit landed on
func _hit_at(p_emitterId: int, p_origin: Vector2) -> int:
	return G_HitServer.hit_circle(p_emitterId, p_origin, 32.0, Vector2(0.0, 64.0),
		C_HitServer.UNLIMITED_HITS, C_CoreServer.NO_ID, _hitData, false).size()


## Records one expectation and prints it when it does not hold. [br]
## @param p_isMet Whether the expectation held [br]
## @param p_description What was expected
func _expect(p_isMet: bool, p_description: String) -> void:
	_checkCount += 1

	if (p_isMet):
		return

	_failureCount += 1
	print("FAIL: " + p_description)


## The three autoload instances are separate objects, yet they share one pool of static data.
func _check_shared_static_data() -> void:
	print("shared static data")
	_clear_world()

	_expect(G_ChunkingServer.get_instance_id() != G_HitServer.get_instance_id()
		and G_HitServer.get_instance_id() != G_TargetingServer.get_instance_id(),
		"the three servers are three distinct autoload instances")

	var l_id: int = _spawn(Vector2(500.0, 600.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())

	_expect(G_HitServer._entityPosition[l_id] == Vector2(500.0, 600.0),
		"G_HitServer reads the exact position G_ChunkingServer wrote, from the same static array")

	G_ChunkingServer.set_position(l_id, Vector2(700.0, 600.0))

	_expect(G_TargetingServer._entityPosition[l_id] == Vector2(700.0, 600.0),
		"a position written through G_ChunkingServer is visible through G_TargetingServer at once")


## Search, approach, combat and flee between two entities of opposing teams.
func _check_targeting_flow() -> void:
	print("targeting flow")
	_clear_world()

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_defender: int = _spawn(Vector2(1100.0, 2000.0), C_CoreServer.TEAM.DEFENDER, M_ModuleManager.new())

	_expect(l_attacker != l_defender, "every entity gets its own id")
	_expect(G_TargetingServer.update_state(l_attacker) == C_TargetingServer.STATE.SEARCH, "a fresh entity searches")
	_expect(G_TargetingServer.acquire_target(l_attacker) == l_defender, "the attacker finds the defender")
	_expect(G_TargetingServer.get_targeters(l_defender) == PackedInt32Array([l_attacker]), "the defender knows its targeter")
	_expect(G_TargetingServer.update_state(l_attacker) == C_TargetingServer.STATE.APPROACH, "out of hit range means approach")
	_expect(G_TargetingServer.get_move_destination(l_attacker) == Vector2(1100.0, 2000.0), "approaching heads for the target")

	G_ChunkingServer.set_position(l_attacker, Vector2(1050.0, 2000.0))
	_expect(G_TargetingServer.update_state(l_attacker) == C_TargetingServer.STATE.COMBAT, "a move from the index reaches targeting")

	_expect(G_TargetingServer.update_state(l_defender) == C_TargetingServer.STATE.FLEE, "a close targeter makes the defender flee")
	_expect(G_TargetingServer.get_move_destination(l_defender).x == C_ChunkingServer.MAP_SIZE.x, "fleeing heads for the own base")

	G_TargetingServer.set_is_invisible(l_defender, true)
	_expect(G_TargetingServer.get_target(l_attacker) == C_CoreServer.NO_ID, "turning invisible drops the targeter")
	_expect(G_TargetingServer.acquire_target(l_attacker) == C_CoreServer.NO_ID, "an invisible entity cannot be found")


## Hits land on opponents only, pass the modules the payload and respect the groups.
func _check_hits() -> void:
	print("hits")
	_clear_world()

	var l_attackerModule: M_ModuleManager = M_ModuleManager.new()
	var l_allyModule: M_ModuleManager = M_ModuleManager.new()
	var l_defenderModule: M_ModuleManager = M_ModuleManager.new()
	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, l_attackerModule)
	var l_defender: int = _spawn(Vector2(1040.0, 2000.0), C_CoreServer.TEAM.DEFENDER, l_defenderModule)
	_spawn(Vector2(1020.0, 2000.0), C_CoreServer.TEAM.ATTACKER, l_allyModule)

	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 1, "a hit lands on the one opponent in reach")
	_expect(l_defenderModule.hitCount == 1 and l_defenderModule.lastHitData == _hitData, "the module of the target gets the payload")
	_expect(l_attackerModule.hitCount == 0, "a hit never lands on its emitter")
	_expect(l_allyModule.hitCount == 0, "a hit never lands on an ally right beside the emitter")

	G_ChunkingServer.set_position(l_defender, Vector2(1500.0, 2000.0))
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "a target moved out of reach is not hit")

	G_ChunkingServer.set_position(l_defender, Vector2(1040.0, 2000.0))
	G_HitServer.set_hurt_groups(l_defender, 0b10)
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "a hit without a matching hurt group does not connect")

	G_HitServer.set_hurt_groups(l_defender, 0b1)
	G_HitServer.set_height_band(l_defender, Vector2(200.0, 300.0))
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "a hit below the band of the target misses")


## Announcing and removing an entity ends every link to it on both servers.
func _check_removal_lifecycle() -> void:
	print("removal lifecycle")
	_clear_world()

	var l_defenderModule: M_ModuleManager = M_ModuleManager.new()
	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_defender: int = _spawn(Vector2(1040.0, 2000.0), C_CoreServer.TEAM.DEFENDER, l_defenderModule)

	G_TargetingServer.acquire_target(l_attacker)
	G_TargetingServer.acquire_target(l_defender)
	A_CoreServer.pre_unregister(l_defender)

	_expect(G_TargetingServer.get_target(l_attacker) == C_CoreServer.NO_ID, "announcing an entity drops its targeters")
	_expect(G_TargetingServer.acquire_target(l_attacker) == C_CoreServer.NO_ID, "an announced entity cannot be found")
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0 and l_defenderModule.hitCount == 0, "an announced entity cannot be hit")
	_expect(G_TargetingServer.get_target(l_defender) == l_attacker, "an announced entity keeps acting until it is removed")

	A_CoreServer.unregister(l_defender)
	_expect(G_TargetingServer.get_targeters(l_attacker).is_empty(), "removing an entity drops its own target")

	A_CoreServer.unregister(l_defender)
	A_CoreServer.release_removed_ids()
	A_CoreServer.release_removed_ids()

	var l_first: int = _spawn_inert(Vector2(3000.0, 2000.0), C_CoreServer.TEAM.DEFENDER)
	var l_second: int = _spawn_inert(Vector2(3000.0, 2000.0), C_CoreServer.TEAM.DEFENDER)
	_expect(l_first == l_defender and l_second != l_defender, "a double removal frees the id only once")


## A reused id starts clean on every server.
func _check_id_reuse() -> void:
	print("id reuse")
	_clear_world()

	var l_curve: Curve = Curve.new()
	l_curve.add_point(Vector2(0.0, 100.0))
	l_curve.add_point(Vector2(100.0, 100.0))

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_defender: int = _spawn(Vector2(1040.0, 2000.0), C_CoreServer.TEAM.DEFENDER, M_ModuleManager.new())
	var l_decoy: int = _spawn(Vector2(1060.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())

	G_HitServer.set_radius_curve(l_defender, l_curve)
	G_TargetingServer.set_has_focus(l_defender, true)
	G_TargetingServer.acquire_target(l_defender)
	G_TargetingServer.acquire_target(l_attacker)

	A_CoreServer.pre_unregister(l_defender)
	A_CoreServer.unregister(l_defender)
	A_CoreServer.release_removed_ids()

	var l_reusedModule: M_ModuleManager = M_ModuleManager.new()
	var l_reused: int = A_CoreServer.register(Vector2(1040.0, 2000.0), 24.0, C_CoreServer.TEAM.DEFENDER, 0b1,
		l_reusedModule, _hitProfile, _targetingData)
	_liveIds.append(l_reused)

	_expect(l_reused == l_defender, "the released id is handed out again")
	_expect(G_TargetingServer.get_target(l_reused) == C_CoreServer.NO_ID, "a reused id holds no target")
	_expect(G_TargetingServer.get_targeters(l_reused).is_empty(), "a reused id has no targeters")
	_expect(G_TargetingServer.get_state(l_reused) == C_TargetingServer.STATE.SEARCH, "a reused id starts searching")
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 1 and l_reusedModule.hitCount == 1, "the reused id registers fresh on every server in one call")
	_expect(G_TargetingServer.acquire_target(l_decoy) == l_reused, "the reused id can be targeted again")


## An entity given zeroed groups is inert: never hit, never searches, but still standing on the index.
func _check_inert_registration() -> void:
	print("inert registration")
	_clear_world()

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_obstacle: int = _spawn_inert(Vector2(1040.0, 2000.0), C_CoreServer.TEAM.DEFENDER)

	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "an entity with a default hit profile carries no hurt groups, so it is never hit")
	_expect(G_TargetingServer.acquire_target(l_attacker) == l_obstacle, "it still sits on the chunking index and can be targeted by its chunking groups")
	_expect(G_TargetingServer.update_state(l_obstacle) == C_TargetingServer.STATE.SEARCH, "a default targeting profile answers with defaults")
	_expect(G_TargetingServer.acquire_target(l_obstacle) == C_CoreServer.NO_ID, "a default targeting profile carries no targeted groups, so it never finds anything")


## Several targeters on one target: dropping one keeps the others, invisibility spares those that see it.
func _check_targeter_chain() -> void:
	print("targeter chain")
	_clear_world()

	var l_defender: int = _spawn(Vector2(2000.0, 2000.0), C_CoreServer.TEAM.DEFENDER, M_ModuleManager.new())
	var l_first: int = _spawn(Vector2(1900.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_second: int = _spawn(Vector2(1900.0, 2100.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_third: int = _spawn(Vector2(1900.0, 1900.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())

	G_TargetingServer.acquire_target(l_first)
	G_TargetingServer.acquire_target(l_second)
	G_TargetingServer.acquire_target(l_third)

	var l_targeters: PackedInt32Array = G_TargetingServer.get_targeters(l_defender)
	l_targeters.sort()
	var l_expectedTargeters: PackedInt32Array = PackedInt32Array([l_first, l_second, l_third])
	l_expectedTargeters.sort()
	_expect(l_targeters == l_expectedTargeters, "three attackers share one target")

	G_TargetingServer.set_can_target_invisible(l_second, true)
	G_TargetingServer.set_is_invisible(l_defender, true)
	_expect(G_TargetingServer.get_targeters(l_defender) == PackedInt32Array([l_second]), "invisibility keeps only the targeter that sees it")
	_expect(G_TargetingServer.get_target(l_first) == C_CoreServer.NO_ID and G_TargetingServer.get_target(l_third) == C_CoreServer.NO_ID,
		"the targeters that lost sight hold no target anymore")

	A_CoreServer.pre_unregister(l_defender)
	_expect(G_TargetingServer.get_targeters(l_defender).is_empty() and G_TargetingServer.get_target(l_second) == C_CoreServer.NO_ID,
		"announcing the target clears the whole chain")


## Ordered hits land in shape order, respect the limit and stop at a blocker.
func _check_ordered_hits() -> void:
	print("ordered hits")
	_clear_world()

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	_spawn(Vector2(1100.0, 2000.0), C_CoreServer.TEAM.DEFENDER, M_ModuleManager.new())
	var l_middle: int = _spawn(Vector2(1200.0, 2000.0), C_CoreServer.TEAM.DEFENDER, M_ModuleManager.new())
	var l_far: int = _spawn(Vector2(1300.0, 2000.0), C_CoreServer.TEAM.DEFENDER, M_ModuleManager.new())

	var l_impacts: PackedVector3Array = G_HitServer.hit_directional_rect(l_attacker, Vector2(1000.0, 2000.0), Vector2.RIGHT,
		400.0, 40.0, Vector2(0.0, 64.0), 2, C_CoreServer.NO_ID, _hitData, C_HitServer.RECT_ORDER.FROM_FRONT)
	_expect(l_impacts.size() == 2 and l_impacts[0].x > l_impacts[1].x, "a rect ordered from the front lands the far target first")

	G_HitServer.set_stop_groups(l_attacker, 0b100)
	G_HitServer.set_hurt_groups(l_middle, 0b101)
	l_impacts = G_HitServer.hit_circle(l_attacker, Vector2(1000.0, 2000.0), 400.0, Vector2(0.0, 64.0),
		C_HitServer.UNLIMITED_HITS, C_CoreServer.NO_ID, _hitData, true)
	_expect(l_impacts.size() == 2, "an ordered hit stops at the first target carrying a stop group")

	l_impacts = G_HitServer.hit_circle(l_attacker, Vector2(1000.0, 2000.0), 400.0, Vector2(0.0, 64.0),
		C_HitServer.UNLIMITED_HITS, C_CoreServer.NO_ID, _hitData, false)
	_expect(l_impacts.size() == 3, "an unordered hit ignores stop groups")

	l_impacts = G_HitServer.hit_sector(l_attacker, Vector2(1000.0, 2000.0), Vector2.RIGHT, 400.0, PI * 0.5,
		Vector2(0.0, 64.0), 1, l_far, _hitData, C_HitServer.SECTOR_ORDER.NONE)
	_expect(l_impacts.size() == 1 and is_equal_approx(l_impacts[0].x, 1300.0 - 24.0), "a preferred target is checked first")


## A module manager that fires a hit while taking one leaves the running hit intact.
func _check_reentrant_hit() -> void:
	print("reentrant hit")
	_clear_world()

	var l_counterData: R_HitData = R_HitData.new()
	var l_reflector: ReentrantModuleManager = ReentrantModuleManager.new()
	var l_secondModule: M_ModuleManager = M_ModuleManager.new()
	var l_attackerModule: M_ModuleManager = M_ModuleManager.new()
	var l_allyModule: M_ModuleManager = M_ModuleManager.new()

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, l_attackerModule)
	var l_reflectorId: int = _spawn(Vector2(1030.0, 2000.0), C_CoreServer.TEAM.DEFENDER, l_reflector)
	_spawn(Vector2(1060.0, 2000.0), C_CoreServer.TEAM.DEFENDER, l_secondModule)
	_spawn(Vector2(980.0, 2000.0), C_CoreServer.TEAM.ATTACKER, l_allyModule)

	l_reflector.ownerId = l_reflectorId
	l_reflector.counterHitData = l_counterData

	var l_impacts: PackedVector3Array = G_HitServer.hit_circle(l_attacker, Vector2(1000.0, 2000.0), 100.0, Vector2(0.0, 64.0),
		C_HitServer.UNLIMITED_HITS, C_CoreServer.NO_ID, _hitData, true)

	_expect(l_impacts.size() == 2, "the running hit still reports both targets")
	_expect(l_secondModule.hitCount == 1 and l_secondModule.lastHitData == _hitData, "the target after the reflector still gets the original payload")
	_expect(l_attackerModule.hitCount == 1 and l_attackerModule.lastHitData == l_counterData, "the attacker only takes the counter hit, never its own")
	_expect(l_allyModule.hitCount == 1 and l_allyModule.lastHitData == l_counterData, "the counter hit lands on both attackers")


## A target announced for removal by an earlier target of the same hit is neither hit nor reported.
func _check_removal_during_dispatch() -> void:
	print("removal during dispatch")
	_clear_world()

	var l_exploder: RemovingModuleManager = RemovingModuleManager.new()
	var l_farModule: M_ModuleManager = M_ModuleManager.new()

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_CoreServer.TEAM.ATTACKER, M_ModuleManager.new())
	_spawn(Vector2(1040.0, 2000.0), C_CoreServer.TEAM.DEFENDER, l_exploder)
	l_exploder.victimId = _spawn(Vector2(1080.0, 2000.0), C_CoreServer.TEAM.DEFENDER, l_farModule)

	var l_impacts: PackedVector3Array = G_HitServer.hit_circle(l_attacker, Vector2(1000.0, 2000.0), 200.0, Vector2(0.0, 64.0),
		C_HitServer.UNLIMITED_HITS, C_CoreServer.NO_ID, _hitData, true)

	_expect(l_exploder.hitCount == 1 and l_farModule.hitCount == 0, "the target removed mid dispatch is not hit")
	_expect(l_impacts.size() == 1, "only the impact that really landed is reported")

#endregion
