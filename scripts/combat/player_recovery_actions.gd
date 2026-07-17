extends RefCounted
## 玩家战斗恢复行为；统一处理回合状态、药品和摸鱼恢复。

var combat: Node
const MAX_MEDICINE_USES := 2
const REST_HEAL_RATIO := 0.20

## 绑定战斗系统协调器。
func _init(combat_system: Node) -> void:
	combat = combat_system

## 消耗一件体力药品并恢复到本场战斗体力上限以内；每场战斗最多服药两次。
func use_item(session: Dictionary, item_id: String) -> Dictionary:
	if int(session.get("player_medicine_uses", 0)) >= MAX_MEDICINE_USES:
		return {"ok": false, "message": "本场已连续服药两次，药力一时难以再化开。"}
	var definition := DataRegistry.get_item(item_id)
	var hp_gain := maxi(0, int(definition.get("effects", {}).get("hp", 0)))
	if str(definition.get("kind", "")) != "medicine" or hp_gain <= 0 or InventorySystem.count(item_id) <= 0:
		return {"ok": false, "message": "身上没有伤药。"}
	var maximum_hp := int(session.get("player_max_hp", combat._player_hp_max()))
	if int(GameState.combat_state.hp) >= maximum_hp:
		return {"ok": false, "message": "体力已满，无需用药。"}
	var turn_check: Dictionary = combat.start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	maximum_hp = int(session.get("player_max_hp", combat._player_hp_max()))
	if int(GameState.combat_state.hp) >= maximum_hp:
		var skipped_result := {"ok": false, "skipped": true, "message": "毒发后体力已贴近新上限，这次用药落了空。"}
		session.log.append(skipped_result.message)
		return skipped_result
	if not InventorySystem.remove_item(item_id):
		return {"ok": false, "message": "身上没有伤药。"}
	var previous_hp := int(GameState.combat_state.hp)
	GameState.combat_state.hp = mini(maximum_hp, previous_hp + hp_gain)
	session.player_hp = GameState.combat_state.hp
	session.player_medicine_uses = int(session.get("player_medicine_uses", 0)) + 1
	var actual_gain := int(GameState.combat_state.hp) - previous_hp
	var message := "你服药调息，体力 +%d。" % actual_gain
	session.log.append(message)
	return {"ok": true, "message": message, "hp_gain": actual_gain}

## 每场仅一次：按 1:1 消耗精力恢复缺失体力，单次封顶为本场体力上限的 20%，
## 体力已满或精力为空时不生效。
func rest(session: Dictionary) -> Dictionary:
	if bool(session.get("player_rest_used", false)):
		var used_result := {"ok": false, "message": "本场已经摸过一次鱼，敌人不会再给你空当。"}
		session.log.append(used_result.message)
		return used_result
	var maximum_hp := int(session.get("player_max_hp", combat._player_hp_max()))
	var missing_hp := maxi(0, maximum_hp - int(GameState.combat_state.hp))
	if missing_hp <= 0:
		var result := {"ok": false, "message": "体力已满，不必摸鱼。"}
		session.log.append(result.message)
		return result
	if int(GameState.combat_state.mp) <= 0:
		var no_mp_result := {"ok": false, "message": "精力不足，摸不了鱼。"}
		session.log.append(no_mp_result.message)
		return no_mp_result
	var turn_check: Dictionary = combat.start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	maximum_hp = int(session.get("player_max_hp", combat._player_hp_max()))
	missing_hp = maxi(0, maximum_hp - int(GameState.combat_state.hp))
	if missing_hp <= 0:
		return {"ok": false, "skipped": true, "message": "毒发后体力已贴近新上限，这次摸鱼落了空。"}
	var heal_cap := maxi(1, int(ceil(float(maximum_hp) * REST_HEAL_RATIO)))
	var amount := mini(int(GameState.combat_state.mp), mini(missing_hp, heal_cap))
	if amount <= 0:
		var result := {"ok": false, "message": "精力不足，摸不了鱼。"}
		session.log.append(result.message)
		return result
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	session.player_hp = GameState.combat_state.hp
	session.player_rest_used = true
	var message := "你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount]
	session.log.append(message)
	return {"ok": true, "message": message, "amount": amount}
