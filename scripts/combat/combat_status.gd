extends RefCounted
## 回合开始时的异常状态结算与玩家濒危状态追踪。

var combat: Node

func _init(combat_system: Node) -> void:
	combat = combat_system

func start_turn(session: Dictionary, side: String) -> Dictionary:
	var status_key := "player_status" if side == "player" else "enemy_status"
	var statuses: Dictionary = session.get(status_key, {})
	var message := ""
	if int(statuses.get("poison", 0)) > 0:
		if side == "player":
			var player_max := maxi(1, int(session.get("player_max_hp", combat._player_hp_max())))
			var drain := maxi(1, int(floor(float(player_max) * 0.10)))
			session.player_max_hp = maxi(1, player_max - drain)
			GameState.combat_state.hp = mini(int(GameState.combat_state.hp), int(session.player_max_hp))
			session.player_hp = GameState.combat_state.hp
			message = "%s中毒发作，体力上限 −%d。" % [combat._player_name(), drain]
		else:
			var enemy_max := maxi(1, int(session.get("enemy_max_hp", session.get("enemy_hp", 1))))
			var enemy_drain := maxi(1, int(floor(float(enemy_max) * 0.10)))
			session.enemy_max_hp = maxi(1, enemy_max - enemy_drain)
			session.enemy_hp = mini(int(session.enemy_hp), int(session.enemy_max_hp))
			message = "%s中毒发作，体力上限 −%d。" % [session.enemy.get("displayName", "敌人"), enemy_drain]
	var skipped := int(statuses.get("paralysis", 0)) > 0
	for status in statuses.keys():
		statuses[status] = int(statuses[status]) - 1
		if int(statuses[status]) <= 0:
			statuses.erase(status)
	session[status_key] = statuses
	if skipped:
		var actor_name: String = str(combat._player_name() if side == "player" else session.enemy.get("displayName", "敌人"))
		message = (message + "，" if not message.is_empty() else "") + "%s麻痹，无法出手！" % actor_name
		session.log.append(message)
		return {"can_act": false, "message": message}
	if not message.is_empty():
		session.log.append(message)
	return {"can_act": true, "message": message}

func add_status(session: Dictionary, side: String, status: String, turns: int) -> void:
	var key := "player_status" if side == "player" else "enemy_status"
	var statuses: Dictionary = session.get(key, {})
	statuses[status] = maxi(int(statuses.get(status, 0)), turns)
	session[key] = statuses

func track_player_state(session: Dictionary) -> void:
	var hp := int(GameState.combat_state.hp)
	var maximum := maxi(1, int(session.get("player_max_hp", combat._player_hp_max())))
	if hp <= 0:
		session.player_reached_zero = true
	elif hp <= int(floor(float(maximum) * 0.15)):
		session.player_near_death = true
