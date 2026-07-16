extends RefCounted
## 战斗展示层：由 game.gd 持有并通过 `game` 反向引用读写共享状态
## （message、battle_panel/battle_content 等 HUD 节点、_display_scale() 等布局辅助方法）。

const BATTLE_HUD_RENDERER := preload("res://scripts/battle/battle_hud_renderer.gd")
const ACTIONS: Array[String] = ["攻击", "绝招", "用药", "摸鱼", "逃跑"]

## 主场景宿主、战斗会话和当前敌人快照。
var game: Node

var active := false
var enemy: Dictionary = {}
var enemy_hp := 0
var session: Dictionary = {}
var lethal := true
## 操作栏、子菜单和本次刷新创建的临时控件状态。
var submenu := ""
var submenu_index := 0
var submenu_items: Array = []
var action_index := 0
var widgets: Array[Control] = []
## 战斗结束后的延迟确认状态。
var ended := false
var pending_result := ""
var pending_player_died := false

## 绑定拥有战斗面板与共享 HUD 状态的主场景。
func _init(owner: Node) -> void:
	game = owner

## 根据邻近人物创建战斗会话并显示初始画面。
func start() -> void:
	if game.nearby_npc_id.is_empty() or not NpcSystem.can_interact(game.nearby_npc_id):
		game.message = "附近没有可战斗的 NPC"
		return
	enemy = NpcSystem.build_instance(game.nearby_npc_id)
	session = CombatSystem.create_session(game.nearby_npc_id, lethal)
	enemy_hp = int(session.get("enemy_hp", game._npc_hp(enemy)))
	action_index = 0
	ended = false
	pending_result = ""
	pending_player_died = false
	active = true
	game._layout_battle_panel()
	game.battle_panel.visible = true
	# 参照项目由思维决定先手；敌方先手时在玩家看到操作栏前先行动一次。
	if str(session.get("turn", "player")) == "enemy":
		CombatSystem.enemy_action(session)
		if _player_is_down():
			_end_defeat()
			return
	refresh()

## 处理主操作栏输入；战斗结束后由确认或取消键退出。
func handle_key(key: Key) -> void:
	if ended:
		if key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			_finish_end()
		return
	if key == KEY_LEFT:
		action_index = posmod(action_index - 1, ACTIONS.size())
		refresh()
	elif key == KEY_RIGHT:
		action_index = posmod(action_index + 1, ACTIONS.size())
		refresh()
	elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_activate_action()

## 执行当前主操作栏选择。
func _activate_action() -> void:
	match action_index:
		0:
			_attack()
		1:
			_open_submenu("ult")
		2:
			_open_submenu("item")
		3:
			_rest()
		4:
			_flee()

## 执行玩家普通攻击，胜负未定时继续敌方回合。
func _attack() -> void:
	var result: Dictionary = CombatSystem.player_attack(session)
	enemy_hp = int(session.get("enemy_hp", enemy_hp))
	if _enemy_is_down():
		_append_victory_line()
		end(BattleResolve.resolve_victory(session, lethal))
	else:
		_enemy_turn()
		if not active: return
		refresh()

## 执行摸鱼恢复；行动被状态跳过时继续敌方回合。
func _rest() -> void:
	var rest_result: Dictionary = CombatSystem.rest(session)
	game.message = rest_result.message
	if rest_result.get("skipped", false):
		_enemy_turn()
		if not active: return
	refresh()

## 尝试逃跑；失败后继续敌方回合。
func _flee() -> void:
	var flee_result: Dictionary = CombatSystem.flee_action(session)
	if flee_result.get("escaped", false):
		end(BattleResolve.resolve_flee(session, lethal))
	else:
		_enemy_turn()
		if not active: return
		refresh()

## 执行一次敌方人工智能行动并检查玩家失败。
func _enemy_turn() -> void:
	CombatSystem.enemy_action(session)
	enemy_hp = int(session.get("enemy_hp", enemy_hp))
	if _player_is_down():
		_end_defeat()

## 按致命或切磋模式判断玩家是否倒下。
func _player_is_down() -> bool:
	return int(GameState.combat_state.hp) <= (0 if lethal else 1)

## 按致命或切磋模式判断敌方是否倒下。
func _enemy_is_down() -> bool:
	return int(session.get("enemy_hp", enemy_hp)) <= (0 if lethal else 1)

## 写入失败战报并生成对应结算。
func _end_defeat() -> void:
	session.log.append("你眼前一黑，倒了下去……" if lethal else "你自愧不敌，拱手认负。")
	end(BattleResolve.resolve_defeat(session, lethal), lethal)

## 按战斗模式追加击败或认负文案。
func _append_victory_line() -> void:
	var enemy_name := str(enemy.get("display_name", game.nearby_npc_id))
	session.log.append("%s倒下了。你胜了！" % enemy_name if lethal else "%s拱手认负。你胜了！" % enemy_name)

## 收集可用药品或已解锁绝招并打开子菜单。
func _open_submenu(kind: String) -> void:
	submenu = kind
	submenu_index = 0
	submenu_items = []
	if kind == "item":
		if int(GameState.combat_state.hp) >= int(session.get("player_max_hp", GameState.player_effective_hp_max())):
			submenu = ""
			game.message = "体力已满，无需用药。"
			refresh()
			return
		for entry in InventorySystem.list_entries("medicine"):
			var item_id := str(entry.get("id", ""))
			if int(DataRegistry.get_item(item_id).get("effects", {}).get("hp", 0)) > 0:
				submenu_items.append(item_id)
	else:
		for ult in SkillSystem.unlocked_ults():
			if int(GameState.combat_state.mp) >= int(ult.get("mp_cost", 0)):
				submenu_items.append(ult)
	if submenu_items.is_empty():
		submenu = ""
		game.message = "身上没有伤药。" if kind == "item" else "没有可放的绝招（精力不足或内功未到）。"
		session.log.append(game.message)
	refresh()

## 处理子菜单导航、返回和选中项执行。
func handle_submenu_key(key: Key) -> void:
	if key == KEY_ESCAPE or key == KEY_LEFT:
		submenu = ""
		refresh()
		return
	if key == KEY_UP:
		submenu_index = posmod(submenu_index - 1, submenu_items.size())
	elif key == KEY_DOWN:
		submenu_index = posmod(submenu_index + 1, submenu_items.size())
	elif key == KEY_SPACE:
		if submenu == "item":
			var item_id := str(submenu_items[submenu_index])
			var item_result: Dictionary = CombatSystem.use_item(session, item_id)
			game.message = str(item_result.get("message", ""))
			submenu = ""
			if item_result.get("skipped", false):
				_enemy_turn()
				if not active: return
		else:
			var ult_result: Dictionary = CombatSystem.use_ult(session, submenu_items[submenu_index])
			if not ult_result.ok:
				game.message = str(ult_result.get("message", ""))
				if ult_result.get("skipped", false):
					_enemy_turn()
					if not active: return
				refresh()
				return
			game.message = str(ult_result.ult.get("name", "绝招"))
			submenu = ""
			enemy_hp = int(session.get("enemy_hp", enemy_hp))
			if _enemy_is_down():
				_append_victory_line()
				end(BattleResolve.resolve_victory(session, lethal))
				return
			_enemy_turn()
			if not active: return
	refresh()

func refresh() -> void:
	## 展示细节由独立渲染器负责，状态机只发起刷新。
	## 渲染器按刷新临时创建，避免与本 RefCounted 状态机形成循环引用。
	BATTLE_HUD_RENDERER.new(self, game).refresh()

## 为测试和旧调用方保留战报矩形兼容入口。
func _report_rect(area: Vector2, scale: float) -> Rect2:
	return BATTLE_HUD_RENDERER.new(self, game).report_rect(area, scale)

## 为测试和旧调用方保留战报文本兼容入口。
func _report_text() -> String:
	return BATTLE_HUD_RENDERER.new(self, game).report_text()

## 为测试和结束流程保留临时控件清理入口。
func _clear_widgets() -> void:
	BATTLE_HUD_RENDERER.new(self, game).clear_widgets()

## 记录结算结果，进入等待确认状态并刷新最终画面。
func end(result_message: String, player_died := false) -> void:
	ended = true
	pending_result = result_message
	pending_player_died = player_died
	submenu = ""
	submenu_items = []
	if not result_message.is_empty(): session.log.append(result_message)
	refresh()

## 关闭战斗面板；玩家死亡时显示结算对白后返回启动场景。
func _finish_end() -> void:
	active = false
	ended = false
	game.battle_panel.visible = false
	_clear_widgets()
	game.message = pending_result
	if pending_player_died:
		var enemy_name := str(enemy.get("display_name", game.nearby_npc_id))
		game._show_dialogue(enemy_name, pending_result, 0.0, func() -> String:
			game.get_tree().change_scene_to_file("res://scenes/splash.tscn")
			return ""
		)
	pending_result = ""
	pending_player_died = false
