extends RefCounted
## 玩家战斗恢复行为；统一处理回合状态、药品和摸鱼恢复。

var combat: Node

## 绑定战斗系统协调器。
func _init(combat_system: Node) -> void:
	combat = combat_system

## 消耗一件体力药品并恢复到本场战斗体力上限以内。
func use_item(session: Dictionary, item_id: String) -> Dictionary:
	var turn_check: Dictionary = combat.start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	var definition := DataRegistry.get_item(item_id)
	var hp_gain := maxi(0, int(definition.get("effects", {}).get("hp", 0)))
	if str(definition.get("kind", "")) != "medicine" or hp_gain <= 0 or not InventorySystem.remove_item(item_id):
		return {"ok": false, "message": "身上没有伤药。"}
	var previous_hp := int(GameState.combat_state.hp)
	var maximum_hp := int(session.get("player_max_hp", combat._player_hp_max()))
	GameState.combat_state.hp = mini(maximum_hp, previous_hp + hp_gain)
	session.player_hp = GameState.combat_state.hp
	var actual_gain := int(GameState.combat_state.hp) - previous_hp
	var message := "你服药调息，体力 +%d。" % hp_gain
	session.log.append(message)
	return {"ok": true, "message": message, "hp_gain": actual_gain}

## 消耗当前精力等量恢复缺失体力，体力已满或精力为空时不生效。
func rest(session: Dictionary) -> Dictionary:
	var turn_check: Dictionary = combat.start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	var maximum_hp := int(session.get("player_max_hp", combat._player_hp_max()))
	var missing_hp := maxi(0, maximum_hp - int(GameState.combat_state.hp))
	if missing_hp <= 0:
		var result := {"ok": false, "message": "体力已满，不必摸鱼。"}
		session.log.append(result.message)
		return result
	var amount := mini(int(GameState.combat_state.mp), missing_hp)
	if amount <= 0:
		var result := {"ok": false, "message": "精力不足，摸不了鱼。"}
		session.log.append(result.message)
		return result
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	session.player_hp = GameState.combat_state.hp
	var message := "你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount]
	session.log.append(message)
	return {"ok": true, "message": message, "amount": amount}
