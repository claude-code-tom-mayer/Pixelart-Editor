extends SceneTree
class_name EndToEndTest
## Drives entities through the chunking, hit and targeting servers the way the game does. [br]
## Run it headless: godot --headless --script res://Tests/EndToEndTest.gd

#region EXPORTS_AND_VARS

## Chunk index of the running check; hands out the id every entity uses on all servers.
var _chunking: ChunkingServer = null

## Hit server of the running check.
var _hits: HitServer = null

## Targeting server of the running check.
var _targeting: TargetingServer = null

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

## Runs every check, prints a summary and quits with a non zero code on failure.
func _init() -> void:
	_hitProfile = R_HitProfile.new()
	_hitProfile.hurtGroups = 0b1
	_hitProfile.hitGroups = 0b1

	_targetingData = R_TargetingData.new()
	_targetingData.targetedGroups = 0b1

	_hitData = R_HitData.new()
	_hitData.damage = 5.0

	_check_targeting_flow()
	_check_hits()
	_check_removal_lifecycle()
	_check_id_reuse()
	_check_partial_registration()
	_check_server_lifetime()

	print("")
	print("%d of %d checks passed" % [_checkCount - _failureCount, _checkCount])
	quit(1 if _failureCount > 0 else 0)


## Builds a fresh chunk index with both servers on top of it.
func _build_servers() -> void:
	_chunking = ChunkingServer.new()
	_hits = HitServer.new(_chunking)
	_targeting = TargetingServer.new(_chunking)


## Registers one entity on all three servers, the way an entity does on spawn. [br]
## @param p_position Start position [br]
## @param p_team Team, a C_ChunkingServer.TEAM value [br]
## @param p_module Module management that receives its hits [br]
## @return The id the entity uses on every server
func _spawn(p_position: Vector2, p_team: int, p_module: M_ModuleManager) -> int:
	var l_id: int = _chunking.register_entity(p_position, 24.0, p_team, 0b1)
	_hits.register(l_id, p_module, _hitProfile)
	_targeting.register(l_id, _targetingData)

	return l_id


## Fires a single target circle hit from an entity at its own position. [br]
## @param p_emitterId The entity that hits [br]
## @param p_origin Where the hit is centered [br]
## @return How many targets the hit landed on
func _hit_at(p_emitterId: int, p_origin: Vector2) -> int:
	return _hits.hit_circle(p_emitterId, p_origin, 32.0, Vector2(0.0, 64.0),
		C_HitServer.UNLIMITED_HITS, C_HitServer.NO_PREFERRED_TARGET, _hitData).size()


## Records one expectation and prints it when it does not hold. [br]
## @param p_isMet Whether the expectation held [br]
## @param p_description What was expected
func _expect(p_isMet: bool, p_description: String) -> void:
	_checkCount += 1

	if (p_isMet):
		return

	_failureCount += 1
	print("FAIL: " + p_description)


## Search, approach, combat and flee between two entities of opposing teams.
func _check_targeting_flow() -> void:
	print("targeting flow")
	_build_servers()

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_ChunkingServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_defender: int = _spawn(Vector2(1100.0, 2000.0), C_ChunkingServer.TEAM.DEFENDER, M_ModuleManager.new())

	_expect(l_attacker != l_defender, "every entity gets its own id")
	_expect(_targeting.update_entity(l_attacker) == C_TargetingServer.STATE.SEARCH, "a fresh entity searches")
	_expect(_targeting.search_target(l_attacker) == l_defender, "the attacker finds the defender")
	_expect(_targeting.get_targeters(l_defender) == PackedInt32Array([l_attacker]), "the defender knows its targeter")
	_expect(_targeting.update_entity(l_attacker) == C_TargetingServer.STATE.APPROACH, "out of hit range means approach")
	_expect(_targeting.get_target_position(l_attacker) == Vector2(1100.0, 2000.0), "approaching heads for the target")

	_chunking.set_position(l_attacker, Vector2(1050.0, 2000.0))
	_expect(_targeting.update_entity(l_attacker) == C_TargetingServer.STATE.COMBAT, "a move from the index reaches targeting")

	_expect(_targeting.update_entity(l_defender) == C_TargetingServer.STATE.FLEE, "a close targeter makes the defender flee")
	_expect(_targeting.get_target_position(l_defender).x == C_ChunkingServer.MAP_SIZE.x, "fleeing heads for the own base")

	_targeting.set_invisible(l_defender, true)
	_expect(_targeting.get_target(l_attacker) == C_TargetingServer.NO_TARGET, "turning invisible drops the targeter")
	_expect(_targeting.search_target(l_attacker) == C_TargetingServer.NO_TARGET, "an invisible entity cannot be found")


## Hits land on opponents only, pass the modules the payload and respect the groups.
func _check_hits() -> void:
	print("hits")
	_build_servers()

	var l_attackerModule: M_ModuleManager = M_ModuleManager.new()
	var l_defenderModule: M_ModuleManager = M_ModuleManager.new()
	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_ChunkingServer.TEAM.ATTACKER, l_attackerModule)
	var l_defender: int = _spawn(Vector2(1040.0, 2000.0), C_ChunkingServer.TEAM.DEFENDER, l_defenderModule)
	var l_ally: int = _spawn(Vector2(1020.0, 2000.0), C_ChunkingServer.TEAM.ATTACKER, M_ModuleManager.new())

	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 1, "a hit lands on the one opponent in reach")
	_expect(l_defenderModule.hitCount == 1 and l_defenderModule.lastHitData == _hitData, "the module of the target gets the payload")
	_expect(l_attackerModule.hitCount == 0, "a hit never lands on its emitter")
	_expect(l_ally != l_attacker, "an ally was placed right beside the emitter")

	_chunking.set_position(l_defender, Vector2(1500.0, 2000.0))
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "a target moved out of reach is not hit")

	_chunking.set_position(l_defender, Vector2(1040.0, 2000.0))
	_hits.set_hurt_groups(l_defender, 0b10)
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "a hit without a matching hurt group does not connect")

	_hits.set_hurt_groups(l_defender, 0b1)
	_hits.set_y_band(l_defender, Vector2(200.0, 300.0))
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "a hit below the band of the target misses")


## Announcing and removing an entity ends every link to it on both servers.
func _check_removal_lifecycle() -> void:
	print("removal lifecycle")
	_build_servers()

	var l_defenderModule: M_ModuleManager = M_ModuleManager.new()
	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_ChunkingServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_defender: int = _spawn(Vector2(1040.0, 2000.0), C_ChunkingServer.TEAM.DEFENDER, l_defenderModule)

	_targeting.search_target(l_attacker)
	_targeting.search_target(l_defender)
	_chunking.pre_unregister_entity(l_defender)

	_expect(_targeting.get_target(l_attacker) == C_TargetingServer.NO_TARGET, "announcing an entity drops its targeters")
	_expect(_targeting.search_target(l_attacker) == C_TargetingServer.NO_TARGET, "an announced entity cannot be found")
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0 and l_defenderModule.hitCount == 0, "an announced entity cannot be hit")
	_expect(_targeting.get_target(l_defender) == l_attacker, "an announced entity keeps acting until it is removed")

	_chunking.unregister_entity(l_defender)
	_expect(_targeting.get_targeters(l_attacker).is_empty(), "removing an entity drops its own target")

	_chunking.unregister_entity(l_defender)
	_chunking.release_removed_ids()
	_chunking.release_removed_ids()

	var l_first: int = _chunking.register_entity(Vector2(3000.0, 2000.0), 24.0, C_ChunkingServer.TEAM.DEFENDER, 0b1)
	var l_second: int = _chunking.register_entity(Vector2(3000.0, 2000.0), 24.0, C_ChunkingServer.TEAM.DEFENDER, 0b1)
	_expect(l_first == l_defender and l_second != l_defender, "a double removal frees the id only once")


## A reused id starts clean on every server.
func _check_id_reuse() -> void:
	print("id reuse")
	_build_servers()

	var l_curve: Curve = Curve.new()
	l_curve.add_point(Vector2(0.0, 100.0))
	l_curve.add_point(Vector2(100.0, 100.0))

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_ChunkingServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_defender: int = _spawn(Vector2(1040.0, 2000.0), C_ChunkingServer.TEAM.DEFENDER, M_ModuleManager.new())
	var l_decoy: int = _spawn(Vector2(1060.0, 2000.0), C_ChunkingServer.TEAM.ATTACKER, M_ModuleManager.new())

	_hits.set_radius_curve(l_defender, l_curve)
	_targeting.set_focused(l_defender, true)
	_targeting.search_target(l_defender)
	_targeting.search_target(l_attacker)

	_chunking.pre_unregister_entity(l_defender)
	_chunking.unregister_entity(l_defender)
	_chunking.release_removed_ids()

	var l_reusedModule: M_ModuleManager = M_ModuleManager.new()
	var l_reused: int = _chunking.register_entity(Vector2(1040.0, 2000.0), 24.0, C_ChunkingServer.TEAM.DEFENDER, 0b1)

	_expect(l_reused == l_defender, "the released id is handed out again")
	_expect(_targeting.get_target(l_reused) == C_TargetingServer.NO_TARGET, "a reused id holds no target")
	_expect(_targeting.get_targeters(l_reused).is_empty(), "a reused id has no targeters")
	_expect(_targeting.get_state(l_reused) == C_TargetingServer.STATE.SEARCH, "a reused id starts searching")
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "a reused id is not hittable before it registers a hit side")

	_hits.register(l_reused, l_reusedModule, _hitProfile)
	_targeting.register(l_reused, _targetingData)
	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 1 and l_reusedModule.hitCount == 1, "the reused id is hit once it registers")
	_expect(_targeting.search_target(l_decoy) == l_reused, "the reused id can be targeted again")


## An entity only needs the servers it uses; the index alone never makes it hittable.
func _check_partial_registration() -> void:
	print("partial registration")
	_build_servers()

	var l_attacker: int = _spawn(Vector2(1000.0, 2000.0), C_ChunkingServer.TEAM.ATTACKER, M_ModuleManager.new())
	var l_obstacle: int = _chunking.register_entity(Vector2(1040.0, 2000.0), 24.0, C_ChunkingServer.TEAM.DEFENDER, 0b1)

	_expect(_hit_at(l_attacker, Vector2(1000.0, 2000.0)) == 0, "an entity without a hit side is never hit")
	_expect(_targeting.search_target(l_attacker) == l_obstacle, "an entity only on the index can still be targeted")
	_expect(_targeting.update_entity(l_obstacle) == C_TargetingServer.STATE.SEARCH, "an unregistered side answers with defaults")


## The index never keeps a server alive, and a freed server stops listening to it.
func _check_server_lifetime() -> void:
	print("server lifetime")
	_build_servers()

	var l_chunkingRef: WeakRef = weakref(_chunking)
	var l_hitsRef: WeakRef = weakref(_hits)

	_hits = null
	_expect(l_hitsRef.get_ref() == null, "dropping the hit server frees it")

	var l_attacker: int = _chunking.register_entity(Vector2(1000.0, 2000.0), 24.0, C_ChunkingServer.TEAM.ATTACKER, 0b1)
	_targeting.register(l_attacker, _targetingData)
	_chunking.unregister_entity(l_attacker)
	_chunking.release_removed_ids()
	_expect(_chunking.register_entity(Vector2.ZERO, 24.0, C_ChunkingServer.TEAM.ATTACKER, 0b1) == l_attacker,
		"the index keeps working without the hit server")

	_chunking = null
	_expect(l_chunkingRef.get_ref() != null, "a server keeps the index it reads alive")

	_targeting = null
	_expect(l_chunkingRef.get_ref() == null, "the index is freed with the last server")

#endregion
