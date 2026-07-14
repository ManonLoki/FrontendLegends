extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var data_registry: Node = get_root().get_node("DataRegistry")
	var game_state: Node = get_root().get_node("GameState")
	var inventory: Node = get_root().get_node("InventorySystem")
	var quest_system: Node = get_root().get_node("QuestSystem")
	var skill_system: Node = get_root().get_node("SkillSystem")
	var combat_system: Node = get_root().get_node("CombatSystem")
	var battle_resolve: Node = get_root().get_node("BattleResolve")
	var npc_system: Node = get_root().get_node("NpcSystem")
	_assert(data_registry.items.size() >= 20, "items registry")
	_assert(data_registry.npcs.size() >= 60, "npcs registry")
	_assert(data_registry.skills.size() >= 20, "skills registry")
	_assert(data_registry.map_files.size() == 25, "map registry")
	var map := TiledMapLoader.new()
	_assert(map.load_file(data_registry.map_files[0]), "TMX load")
	_assert(map.width > 0 and map.height > 0, "TMX dimensions")
	_assert(map.layers.has("Road"), "Road layer")
	_assert(map.tilesets.size() >= 2, "TMX tilesets")
	var road_gids: PackedInt32Array = map.layers.get("Road", PackedInt32Array())
	var sample_gid := 0
	for gid in road_gids:
		if gid != 0:
			sample_gid = gid
			break
	_assert(not map.tile_region(sample_gid).is_empty(), "TMX tile texture")
	_assert(not map.transaction_objects().is_empty(), "TMX Transaction objects")
	var spawn_map_found := false
	for map_path in data_registry.map_files:
		var every_map := TiledMapLoader.new()
		_assert(every_map.load_file(map_path), "TMX load: " + map_path)
		_assert(every_map.width > 0 and every_map.height > 0, "TMX size: " + map_path)
		spawn_map_found = spawn_map_found or not every_map.spawn_point().is_empty()
		for transaction in every_map.transaction_objects():
			var properties: Dictionary = transaction.get("properties", {})
			_assert(not str(properties.get("from", "")).is_empty() and not str(properties.get("to", "")).is_empty(), "Transaction endpoints: " + map_path)
			var transaction_tile := Vector2i(int(floor(float(transaction.get("x", 0)) / every_map.tile_width)), int(floor(float(transaction.get("y", 0)) / every_map.tile_height)))
			_assert(not every_map.object_at_tile(transaction_tile.x, transaction_tile.y).is_empty(), "Object lookup: " + map_path)
	_assert(spawn_map_found, "SpawnPoint map")
	var npc_objects := map.npc_objects()
	_assert(not npc_objects.is_empty(), "TMX NPC objects")
	game_state.create_profile("smoke")
	_assert(game_state.has_profile(), "profile creation")
	game_state.profile.vitals.age = 18
	_assert(skill_system.level("basicStrength") == 1, "default skill")
	game_state.profile.vitals.food = 0
	game_state.profile.vitals.water = 0
	_assert(inventory.add_item("fagun"), "inventory add")
	_assert(inventory.count("fagun") == 1, "inventory count")
	_assert(inventory.use_item("fagun").ok, "consumable use")
	game_state.profile.vitals.money = 1000
	_assert(inventory.buy_item("nai_cha_mei_mei", "linxing_kafei").ok, "vendor buy")
	_assert(inventory.use_item("linxing_kafei").ok, "consumable cooldown first use")
	_assert(not inventory.use_item("linxing_kafei").ok, "item cooldown")
	_assert(inventory.add_item("shuangfeiyan_jianshu"), "equipment add")
	_assert(inventory.equip_item("shuangfeiyan_jianshu").ok, "equipment equip")
	_assert(game_state.equipment.weapon == "shuangfeiyan_jianshu", "equipment slot")
	_assert(inventory.add_item("ar_yanjing") and inventory.add_item("chongdianbao"), "accessory add")
	_assert(inventory.equip_item("ar_yanjing").ok and inventory.equip_item("chongdianbao").ok, "dual accessory equip")
	_assert(game_state.equipment.accessory1 == "ar_yanjing" and game_state.equipment.accessory2 == "chongdianbao", "dual accessory slots")
	_assert(quest_system.offer("novice_darkxue_project").ok, "quest offer")
	_assert(quest_system.complete("novice_darkxue_project").ok, "quest complete")
	_assert(not quest_system.interact_npc("dao_shi").is_empty(), "quest NPC talk")
	_assert(quest_system.offer_generator("ring_cunzhang").ok, "ring quest offer")
	var ring_result: Dictionary = quest_system.advance_generator("ring_cunzhang", 10)
	_assert(ring_result.ok and ring_result.complete, "ring quest complete")
	var bounty: Dictionary = quest_system.offer_bounty()
	_assert(bounty.ok and not quest_system.get_bounty_target().is_empty(), "bounty target")
	_assert(not quest_system.active.get("generator:bountyring_xiaobuer", {}).get("reward", {}).is_empty(), "bounty reward")
	var bounty_id := str(bounty.target.get("target_id", ""))
	_assert(npc_system.can_interact(bounty_id), "runtime bounty NPC")
	_assert(not npc_system.build_instance(bounty_id).is_empty(), "runtime bounty instance")
	_assert(not quest_system.on_enemy_defeated(bounty_id).is_empty(), "bounty victory reward")
	var kill_ring: Dictionary = quest_system.offer_generator("killring_huoyanwang")
	_assert(kill_ring.ok, "kill ring offer")
	_assert(quest_system.list_active().has("generator:killring_huoyanwang"), "kill ring active")
	var abandoned: Dictionary = quest_system.abandon_active()
	_assert(abandoned.ok, "quest abandon result")
	_assert(quest_system.abandon_active().ok, "kill ring abandon result")
	_assert(quest_system.list_active().is_empty(), "quest abandon clear")
	var combat_session: Dictionary = combat_system.create_session("douglas_crockford")
	var combat_result: Dictionary = combat_system.player_attack(combat_session)
	_assert(combat_result.has("damage") and combat_session.has("enemy_hp"), "battle session")
	var npc_ults: Array = combat_system._npc_ults(npc_system.build_instance("douglas_crockford"))
	_assert(not npc_ults.is_empty(), "NPC ultimate derivation")
	combat_session.enemy_mp = 100
	var enemy_ult: Dictionary = combat_system._enemy_use_ult(combat_session, npc_ults[0])
	_assert(enemy_ult.has("damage") and int(combat_session.enemy_mp) < 100, "NPC ultimate action")
	game_state.profile.skills.levels["ng_arch_zone"] = 30
	_assert(skill_system.equip("ng_arch_zone").ok, "sect skill equip")
	game_state.combat_state.mp = 100
	_assert(skill_system.set_force_power(5).ok and skill_system.force_power() == 5, "force power")
	game_state.profile.sect = "NG神教"
	game_state.profile.skills.levels["ng_code_decorator"] = 50
	_assert(skill_system.equip("ng_code_decorator").ok and not skill_system.unlocked_moves().is_empty(), "passive sect moves")
	game_state.profile.sect = "香草派"
	game_state.profile.master = "douglas_crockford"
	game_state.profile.vitals.potential = 10
	game_state.profile.vitals.money = 10000
	var learn_options: Array[String] = skill_system.learn_options_for_npc("douglas_crockford")
	_assert("vanilla_code_dom" in learn_options, "teacher stock")
	var learn_progress: Dictionary = skill_system.learn_tick("douglas_crockford", "vanilla_code_dom")
	_assert(not learn_progress.is_empty() and int(game_state.profile.vitals.potential) < 10, "learning progress tick")
	_assert(skill_system.learn_options_for_npc("shu_yan").has("literacy"), "independent tutor stock")
	var ult_result: Dictionary = combat_system.use_ult(combat_session)
	_assert(ult_result.ok and ult_result.has("damage"), "sect ultimate")
	combat_system.add_status(combat_session, "enemy", "paralysis", 1)
	var skipped: Dictionary = combat_system.enemy_attack(combat_session)
	_assert(skipped.get("skipped", false), "paralysis status")
	combat_system.add_status(combat_session, "enemy", "poison", 1)
	var poison_turn: Dictionary = combat_system.start_turn(combat_session, "enemy")
	_assert(poison_turn.can_act, "poison tick")
	game_state.combat_state.hp = maxi(1, int(game_state.combat_state.hp) - 10)
	var rest_result: Dictionary = combat_system.rest(combat_session)
	_assert(rest_result.ok, "battle rest")
	combat_system.add_status(combat_session, "enemy", "weakness", 1)
	var weakness_attack: Dictionary = combat_system.player_attack(combat_session)
	_assert(weakness_attack.has("damage"), "weakness status")
	var victory_text: String = battle_resolve.resolve_victory(combat_session)
	_assert(not victory_text.is_empty() and npc_system.is_defeated("douglas_crockford"), "battle resolve")
	var spar_session: Dictionary = combat_system.create_session("john_resig")
	game_state.combat_state.injury = 0
	game_state.combat_state.hp = maxi(1, int(spar_session.initial_player_hp) - 20)
	var spar_text: String = battle_resolve.resolve_victory(spar_session, false)
	_assert(not spar_text.is_empty() and int(game_state.combat_state.injury) == 0, "spar has no injury penalty")
	game_state.combat_state.mp = 0
	var meditation: Dictionary = skill_system.meditate_tick()
	_assert(meditation.ok, "meditation")
	var attack: Dictionary = game_state.resolve_attack(8.0, {"strength": 5, "agility": 5, "constitution": 5, "wisdom": 5}, {"strength": 4, "agility": 4, "constitution": 4, "wisdom": 4}, 10.0)
	_assert(attack.has("damage"), "combat result")
	game_state.delete_save()
	print("FrontendLegends smoke test passed")
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("Smoke test failed: " + label)
		quit(1)
