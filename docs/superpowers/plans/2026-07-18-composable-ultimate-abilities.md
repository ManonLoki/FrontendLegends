# Composable Ultimate Abilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four hard-coded ultimate branches with level-scaled combo, guaranteed abnormal, guaranteed-hit damage, and HP/MP drain abilities while preserving existing ordinary-move status procs and allowing ordinary moves to reuse guaranteed-hit and drain effects.

**Architecture:** Add a pure `combat_ability_rules.gd` module for curves and normalized effect dictionaries, plus a bound `combat_move_effects.gd` service for existing move bonus/status behavior and post-damage resource transfer. `CombatSystem` remains the authoritative attack pipeline, `ultimate_actions.gd` only orchestrates abilities, and player/NPC loadout builders share one standard ultimate constructor.

**Tech Stack:** Godot 4.7, GDScript, JSON skill data, headless `SceneTree` regression tests, repository-safe `tools/godot-safe.sh` launcher.

## Global Constraints

- Godot scenes and GDScript runtime behavior are the authoritative implementation.
- Never invoke the Godot binary directly; all tests use `./tools/godot-safe.sh` or `./tools/run-godot-tests.sh`.
- Keep `ATTACK_MOVE_STATUS_TABLE` and its 20/40/50/70/80/90 ordinary-attack status behavior unchanged.
- Preserve the combat order and all four attributes, equipped skills, equipment, statuses, injury, MP, force power, and explicit NPC configuration as combat inputs.
- Player and NPC ultimate/effect calculations must use the same functions.
- Do not change save fields or migrate saves.
- Do not modify protected `scripts/game_battle_ui.gd`, `scripts/ui_progress_meter.gd`, protected scenes, or `scripts/game.gd` HUD layout functions.
- Keep every project-owned GDScript at or below the 300-line target and absolutely below 500 lines.
- Preserve all unrelated dirty-worktree changes; stage and commit only files owned by the current task.

---

### Task 1: Pure Level-Scaled Ability Rules

**Files:**
- Create: `scripts/combat/combat_ability_rules.gd`
- Create: `tests/combat/ultimate_ability_rules_test.gd`
- Modify: `tools/run-godot-tests.sh`

**Interfaces:**
- Consumes: an equipped sect architecture level as `int` and an ultimate dictionary containing `abilities` and `inner_level`.
- Produces: `progress(int) -> float`, `multi_hits(int) -> int`, `multi_power(int) -> float`, `abnormal_count(int) -> int`, `guaranteed_damage_scale(int) -> float`, `drain_hp_ratio(int) -> float`, `drain_mp_ratio(int) -> float`, and `attack_effects(Dictionary) -> Dictionary`.

- [ ] **Step 1: Write the failing pure-rules test**

Create `tests/combat/ultimate_ability_rules_test.gd`:

```gdscript
extends SceneTree

const RULES := preload("res://scripts/combat/combat_ability_rules.gd")

var failures: Array[String] = []

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_assert_true([RULES.multi_hits(30), RULES.multi_hits(50), RULES.multi_hits(75), RULES.multi_hits(100)] == [3, 4, 5, 6], "连击次数必须按30/50/75/100级成长为3/4/5/6")
	_assert_true([RULES.multi_power(30), RULES.multi_power(50), RULES.multi_power(75), RULES.multi_power(100)] == [0.65, 0.60, 0.55, 0.50], "连击逐击倍率必须随次数调整")
	_assert_true(RULES.abnormal_count(30) == 1 and RULES.abnormal_count(79) == 1 and RULES.abnormal_count(80) == 2 and RULES.abnormal_count(100) == 2, "异常数量必须在80级从1种增长到2种")
	_assert_true(is_equal_approx(RULES.guaranteed_damage_scale(30), 1.5) and is_equal_approx(RULES.guaranteed_damage_scale(100), 2.0), "必中伤害必须从1.5倍成长到2倍")
	_assert_true(is_equal_approx(RULES.drain_hp_ratio(30), 0.20) and is_equal_approx(RULES.drain_hp_ratio(100), 0.35), "吸血比例必须从20%成长到35%")
	_assert_true(is_equal_approx(RULES.drain_mp_ratio(30), 0.08) and is_equal_approx(RULES.drain_mp_ratio(100), 0.15), "吸精比例必须从8%成长到15%")
	var guaranteed := RULES.attack_effects({"abilities": ["guaranteed_hit"], "inner_level": 65})
	_assert_true(bool(guaranteed.guaranteedHit) and is_equal_approx(float(guaranteed.damageScale), 1.75), "必中绝招必须生成标准攻击效果")
	var drains := RULES.attack_effects({"abilities": ["drain_hp", "drain_mp"], "inner_level": 100})
	_assert_true(is_equal_approx(float(drains.drainHpRatio), 0.35) and is_equal_approx(float(drains.drainMpMaxRatio), 0.15), "吸取能力必须生成标准攻击效果")
	print("ultimate_ability_rules_test: PASS" if failures.is_empty() else "ultimate_ability_rules_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```sh
./tools/godot-safe.sh --headless --script res://tests/combat/ultimate_ability_rules_test.gd
```

Expected: non-zero exit with a preload error because `combat_ability_rules.gd` does not exist.

- [ ] **Step 3: Implement the pure rules**

Create `scripts/combat/combat_ability_rules.gd`:

```gdscript
extends RefCounted
## 组合式绝招与普通招式共用的纯数值规则。

const MIN_INNER_LEVEL := 30
const MAX_INNER_LEVEL := 100

static func progress(inner_level: int) -> float:
	return clampf(float(inner_level - MIN_INNER_LEVEL) / float(MAX_INNER_LEVEL - MIN_INNER_LEVEL), 0.0, 1.0)

static func multi_hits(inner_level: int) -> int:
	if inner_level >= 100: return 6
	if inner_level >= 75: return 5
	if inner_level >= 50: return 4
	return 3

static func multi_power(inner_level: int) -> float:
	return {3: 0.65, 4: 0.60, 5: 0.55, 6: 0.50}[multi_hits(inner_level)]

static func abnormal_count(inner_level: int) -> int:
	return 2 if inner_level >= 80 else 1

static func guaranteed_damage_scale(inner_level: int) -> float:
	return 1.5 + progress(inner_level) * 0.5

static func drain_hp_ratio(inner_level: int) -> float:
	return 0.20 + progress(inner_level) * 0.15

static func drain_mp_ratio(inner_level: int) -> float:
	return 0.08 + progress(inner_level) * 0.07

static func attack_effects(ult: Dictionary) -> Dictionary:
	var abilities: Array = ult.get("abilities", [])
	var level := int(ult.get("inner_level", MIN_INNER_LEVEL))
	var result := {}
	if "guaranteed_hit" in abilities:
		result.guaranteedHit = true
		result.damageScale = guaranteed_damage_scale(level)
	if "drain_hp" in abilities: result.drainHpRatio = drain_hp_ratio(level)
	if "drain_mp" in abilities: result.drainMpMaxRatio = drain_mp_ratio(level)
	return result
```

- [ ] **Step 4: Add the rules test to the safe aggregate runner**

Insert after `combat_alignment_test.gd` in `tools/run-godot-tests.sh`:

```sh
"$tool_dir/godot-safe.sh" --headless --script res://tests/combat/ultimate_ability_rules_test.gd
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run the Step 2 command again.

Expected: `ultimate_ability_rules_test: PASS`, exit 0.

- [ ] **Step 6: Commit Task 1**

```sh
git add scripts/combat/combat_ability_rules.gd tests/combat/ultimate_ability_rules_test.gd tools/run-godot-tests.sh
git commit -m "feat: add level-scaled ultimate ability rules"
```

---

### Task 2: Shared Player/NPC Ultimate Construction and Skill Data

**Files:**
- Modify: `assets/Data/skills.json`
- Modify: `scripts/skills/skill_loadout.gd`
- Modify: `scripts/combat/enemy_ai.gd`
- Modify: `tests/combat/ultimate_ability_rules_test.gd`

**Interfaces:**
- Consumes: `ult.abilitySets`, `ult.mpCosts`, tier number, sect architecture level, and existing inner-power total.
- Produces: `SkillLoadout.build_ult(config: Dictionary, tier: int, inner_power: int, inner_level: int) -> Dictionary`, shared by player and NPC builders.

- [ ] **Step 1: Extend the focused test with standard-dictionary assertions**

Add before the final print in `ultimate_ability_rules_test.gd`:

```gdscript
const LOADOUT := preload("res://scripts/skills/skill_loadout.gd")

var config := {
	"key": "test", "names": ["一档", "二档"],
	"abilitySets": [["drain_hp"], ["drain_mp"]], "mpCosts": [35, 60],
}
var tier_one := LOADOUT.build_ult(config, 1, 190, 80)
var tier_two := LOADOUT.build_ult(config, 2, 190, 80)
_assert_true(tier_one.abilities == ["drain_hp"] and tier_two.abilities == ["drain_mp"], "两档绝招必须携带各自能力")
_assert_true(int(tier_one.inner_level) == 80 and int(tier_one.inner_power) == 190, "标准绝招必须区分特性等级与攻击内功")
_assert_true(int(tier_one.mp_cost) == 35 and int(tier_two.mp_cost) == 60, "精力消耗必须由绝招数据提供")
```

Place the `LOADOUT` preload beside the existing `RULES` preload, not inside `_initialize()`.

- [ ] **Step 2: Run the focused test to verify it fails**

Run the Task 1 test command.

Expected: FAIL because `SkillLoadout.build_ult` does not exist.

- [ ] **Step 3: Replace old ultimate kinds with tiered ability data**

For the four architecture skills in `assets/Data/skills.json`, preserve names and keys and replace `kind` with:

```json
"abilitySets": [["multi"], ["multi"]],
"mpCosts": [25, 45]
```

for NG神教;

```json
"abilitySets": [["abnormal"], ["abnormal"]],
"mpCosts": [30, 50]
```

for 香草派;

```json
"abilitySets": [["drain_hp"], ["drain_mp"]],
"mpCosts": [35, 60]
```

for 量子仙宗; and

```json
"abilitySets": [["guaranteed_hit"], ["guaranteed_hit"]],
"mpCosts": [40, 70]
```

for 鱿鱼山庄.

- [ ] **Step 4: Add the shared standard constructor**

In `skill_loadout.gd`, remove `ULT_MP_COSTS`, change `_make_ult` to accept `inner_level`, and add:

```gdscript
static func build_ult(config: Dictionary, tier: int, inner_power: int, inner_level: int) -> Dictionary:
	var index := clampi(tier - 1, 0, 1)
	var names: Array = config.get("names", ["绝招", "绝招"])
	var sets: Array = config.get("abilitySets", [[], []])
	var costs: Array = config.get("mpCosts", [40, 70])
	var unlock_level := ULT_TIER1_ARCH_LEVEL if tier == 1 else ULT_TIER2_ARCH_LEVEL
	return {
		"id": "ult:%s:%d" % [config.get("key", "sect"), unlock_level],
		"name": names[index], "tier": tier,
		"inner_power": inner_power, "inner_level": inner_level,
		"mp_cost": int(costs[index]), "abilities": sets[index].duplicate(),
	}

func _make_ult(config: Dictionary, tier: int, inner_power: int, inner_level: int) -> Dictionary:
	return build_ult(config, tier, inner_power, inner_level)
```

Update both calls in `unlocked_ults()` to pass `arch_level`.

- [ ] **Step 5: Make NPC construction call the same constructor**

Replace the duplicated kind/name/cost construction in `enemy_ai.gd:npc_ults()` with:

```gdscript
if level >= SKILL_LOADOUT.ULT_TIER1_ARCH_LEVEL:
	result.append(SKILL_LOADOUT.build_ult(config, 1, inner_power, level))
if level >= SKILL_LOADOUT.ULT_TIER2_ARCH_LEVEL:
	result.append(SKILL_LOADOUT.build_ult(config, 2, inner_power, level))
```

- [ ] **Step 6: Run focused and existing combat tests**

Run:

```sh
./tools/godot-safe.sh --headless --script res://tests/combat/ultimate_ability_rules_test.gd
./tools/godot-safe.sh --headless --script res://tests/combat_alignment_test.gd
```

Expected: both tests PASS. Task 2 changes construction only; the executor remains backward-tolerant until Task 4 replaces its branches.

- [ ] **Step 7: Commit Task 2**

```sh
git add assets/Data/skills.json scripts/skills/skill_loadout.gd scripts/combat/enemy_ai.gd tests/combat/ultimate_ability_rules_test.gd
git commit -m "refactor: build player and npc ultimates from abilities"
```

---

### Task 3: Guaranteed-Hit and Reusable Ordinary-Move Effects

**Files:**
- Create: `scripts/combat/combat_move_effects.gd`
- Create: `tests/combat/combat_move_effects_test.gd`
- Modify: `scripts/game_state.gd`
- Modify: `scripts/combat_system.gd`
- Modify: `scripts/combat/combat_rules.gd`
- Modify: `scripts/skills/skill_loadout.gd`
- Modify: `tools/run-godot-tests.sh`

**Interfaces:**
- Consumes: external `attack_effects`, optional ordinary-move `combat_effects`, attack result, target HP before damage, and battle session.
- Produces: `merged(external, move) -> Dictionary`, `apply_move_bonus(session, side, move, result) -> String`, and `apply_drain(session, player_side, actual_damage, effects) -> String`.

- [ ] **Step 1: Write failing guaranteed-hit and drain-calculation tests**

Create `tests/combat/combat_move_effects_test.gd` with this harness and `_initialize()` body:

```gdscript
extends SceneTree

const TEST_ENEMY_ID := "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"
const TEST_SKILL_ID := "__ordinary_effect_skill__"
const BASIC_ARCH_ID := "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"

var failures: Array[String] = []

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var state = root.get_node("GameState")
	var combat = root.get_node("CombatSystem")
	state.use_test_save_path("combat_move_effects")
state.delete_save()
state.create_profile("能力测试", {"strength": 25, "agility": 1, "constitution": 25, "wisdom": 25})

for index in 100:
	var result := state.resolve_attack(100.0, {"agility": 1, "wisdom": 1}, {"agility": 1000}, 0.0, 0.0, 100.0, 0.0, 0.0, true)
	_assert_true(bool(result.hit), "必中攻击不得被基础命中判定避开，第%d次失败" % index)

var parried := false
for index in 100:
	var result := state.resolve_attack(100.0, {"agility": 1, "wisdom": 1}, {"strength": 1000}, 0.0, 0.0, 0.0, 1.0, 0.0, true)
	parried = parried or bool(result.parried)
_assert_true(parried, "必中不得绕过招架阶段")

	var merged := combat.move_effects.merged({"guaranteedHit": true}, {"combat_effects": {"damageScale": 1.5, "drainHpRatio": 0.2}})
	_assert_true(bool(merged.guaranteedHit) and float(merged.damageScale) == 1.5 and float(merged.drainHpRatio) == 0.2, "绝招与普通招式效果必须合并")

	var registry = root.get_node("DataRegistry")
	var skill_system = root.get_node("SkillSystem")
	registry.skills[TEST_SKILL_ID] = {
		"name": "测试普通功法", "category": "sect", "sect": "测试门派", "theme": "code",
		"moves": [{
			"unlockLevel": 10, "name": "测试复合招式",
			"combatEffects": {"guaranteedHit": true, "damageScale": 1.5, "drainHpRatio": 0.2, "drainMpMaxRatio": 0.08},
		}],
	}
	state.profile.sect = "测试门派"
	state.profile.vitals.cultivation = 100
	var skill_state: Dictionary = skill_system.ensure_skills()
	skill_state.levels[BASIC_ARCH_ID] = 80
	skill_state.equipped_basic.arch = BASIC_ARCH_ID
	skill_state.levels[TEST_SKILL_ID] = 100
	skill_state.equipped_special.code = TEST_SKILL_ID
	var session := combat.create_session(TEST_ENEMY_ID, true)
	session.enemy.attributes.agility = 100000
	session.enemy_hp = 100000
	session.enemy_max_hp = 100000
	session.enemy_mp = session.enemy_mp_max
	state.combat_state.hp = maxi(1, int(session.player_max_hp) - 100)
	state.combat_state.mp = 0
	seed(37)
	var triggered := false
	for index in 200:
		var hp_before := int(state.combat_state.hp)
		var mp_before := int(state.combat_state.mp)
		var result := combat.player_attack(session, true)
		if str(session.log[-1]).contains("测试复合招式"):
			triggered = true
			_assert_true(bool(result.hit), "带必中效果的普通招式不得落空")
			_assert_true(int(state.combat_state.hp) > hp_before and int(state.combat_state.mp) > mp_before, "普通招式必须执行吸血和吸精效果")
			break
	_assert_true(triggered, "固定随机种子下必须触发测试普通招式")
	registry.skills.erase(TEST_SKILL_ID)

	state.delete_save()
	print("combat_move_effects_test: PASS" if failures.is_empty() else "combat_move_effects_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: Run the test and verify it fails**

```sh
./tools/godot-safe.sh --headless --script res://tests/combat/combat_move_effects_test.gd
```

Expected: parser/signature failure because the ninth `guaranteed_hit` argument and `combat.move_effects` do not exist.

- [ ] **Step 3: Add an explicit guaranteed-hit argument without changing landed-attack stages**

Change `GameState.resolve_attack` to:

```gdscript
func resolve_attack(attack_power: float, attacker: Dictionary, defender: Dictionary, defense: float, hit_bonus := 0.0, dodge_bonus := 0.0, parry_bonus := 0.0, crit_bonus := 0.0, guaranteed_hit := false) -> Dictionary:
	var hit_rate := clampf(combat_hit_rate(attacker, defender) + float(hit_bonus) - float(dodge_bonus), MIN_HIT_RATE, MAX_HIT_RATE)
	if not bool(guaranteed_hit) and randf() >= hit_rate:
		return {"hit": false, "parried": false, "crit": false, "damage": 0}
	return resolve_landed_attack(attack_power, attacker, defender, defense, parry_bonus, crit_bonus)
```

- [ ] **Step 4: Create the move-effects service and migrate existing move status behavior unchanged**

Create `combat_move_effects.gd` with:

```gdscript
extends RefCounted
## 普通招式附加伤害/状态与命中后资源吸取服务。

var combat: Node

func _init(combat_system: Node) -> void:
	combat = combat_system

func merged(external: Dictionary, move: Dictionary) -> Dictionary:
	var result := external.duplicate(true)
	for key in move.get("combat_effects", {}):
		result[key] = move.combat_effects[key]
	return result

func apply_move_bonus(session: Dictionary, side: String, move: Dictionary, result: Dictionary) -> String:
	if move.is_empty(): return ""
	var status := combat._roll_attack_move_status(move)
	var extra := int(floor(8.0 + maxi(0, int(move.get("level", 0)) - int(move.get("unlock", 0))) * 0.6))
	if not status.is_empty(): extra = int(floor(float(extra) * 0.5))
	result.damage += extra
	var tag := "（招式+%d）" % extra
	if not status.is_empty():
		var turns := randi_range(1, 3)
		var target := "enemy" if side == "player" else "player"
		combat.add_status(session, target, str(status.kind), turns)
		tag += "（施加%s%d回合）" % [combat._status_name(str(status.kind)), turns]
	return tag

func apply_drain(session: Dictionary, player_side: bool, actual_damage: int, effects: Dictionary) -> String:
	var tags := ""
	var hp_ratio := maxf(0.0, float(effects.get("drainHpRatio", 0.0)))
	if hp_ratio > 0.0 and actual_damage > 0:
		var wanted := int(floor(float(actual_damage) * hp_ratio))
		var healed := _heal_attacker(session, player_side, wanted)
		if healed > 0: tags += "（吸血+%d）" % healed
	var mp_ratio := maxf(0.0, float(effects.get("drainMpMaxRatio", 0.0)))
	if mp_ratio > 0.0:
		var drained := _transfer_mp(session, player_side, mp_ratio)
		if drained > 0: tags += "（吸精+%d）" % drained
	return tags
```

Add these helpers directly below `apply_drain`:

```gdscript
func _heal_attacker(session: Dictionary, player_side: bool, wanted: int) -> int:
	if wanted <= 0: return 0
	if player_side:
		var current := int(GameState.combat_state.hp)
		var maximum := maxi(1, int(session.get("player_max_hp", combat._player_hp_max())))
		var healed := mini(wanted, maxi(0, maximum - current))
		GameState.combat_state.hp = clampi(current + healed, 0, maximum)
		session.player_hp = GameState.combat_state.hp
		return healed
	var enemy_current := int(session.get("enemy_hp", 0))
	var enemy_maximum := maxi(1, int(session.get("enemy_max_hp", enemy_current)))
	var enemy_healed := mini(wanted, maxi(0, enemy_maximum - enemy_current))
	session.enemy_hp = clampi(enemy_current + enemy_healed, 0, enemy_maximum)
	return enemy_healed

func _transfer_mp(session: Dictionary, player_side: bool, ratio: float) -> int:
	if player_side:
		var target_max := maxi(0, int(session.get("enemy_mp_max", 0)))
		var target_current := maxi(0, int(session.get("enemy_mp", 0)))
		var attacker_max := maxi(0, GameState.player_mp_max())
		var attacker_current := maxi(0, int(GameState.combat_state.mp))
		var amount := mini(int(floor(float(target_max) * ratio)), mini(target_current, maxi(0, attacker_max - attacker_current)))
		session.enemy_mp = target_current - amount
		GameState.combat_state.mp = attacker_current + amount
		return amount
	var player_max := maxi(0, GameState.player_mp_max())
	var player_current := maxi(0, int(GameState.combat_state.mp))
	var enemy_max := maxi(0, int(session.get("enemy_mp_max", 0)))
	var enemy_current := maxi(0, int(session.get("enemy_mp", 0)))
	var enemy_amount := mini(int(floor(float(player_max) * ratio)), mini(player_current, maxi(0, enemy_max - enemy_current)))
	GameState.combat_state.mp = player_current - enemy_amount
	session.enemy_mp = enemy_current + enemy_amount
	return enemy_amount
```

- [ ] **Step 5: Preserve optional ordinary-move data in both move builders**

Add this field to dictionaries returned by `skill_loadout.gd:unlocked_moves()` and `combat_rules.gd:npc_move()`:

```gdscript
"combat_effects": move.get("combatEffects", {}).duplicate(true)
```

Do not edit `ATTACK_MOVE_STATUS_TABLE`, `roll_attack_move_status`, or their probabilities.

- [ ] **Step 6: Bind the service and integrate attack options without growing `combat_system.gd` past 300 lines**

Add:

```gdscript
const COMBAT_MOVE_EFFECTS := preload("res://scripts/combat/combat_move_effects.gd")
@onready var move_effects := COMBAT_MOVE_EFFECTS.new(self)
```

Append `attack_effects: Dictionary = {}` to both `player_attack` and `enemy_attack`. After selecting `attack_move`, merge effects and read:

```gdscript
var effects := move_effects.merged(attack_effects, attack_move)
var guaranteed := bool(effects.get("guaranteedHit", false))
```

Pass `guaranteed` as the ninth `resolve_attack` argument, skip the defender dodge-move branch when guaranteed, multiply the existing positional `damage_scale` by `float(effects.get("damageScale", 1.0))`, and call:

```gdscript
var hp_before := int(session.enemy_hp) # player path
# existing target HP deduction
var drain_tag := move_effects.apply_drain(session, true, hp_before - int(session.enemy_hp), effects)
```

Use `GameState.combat_state.hp` and `player_side = false` in the enemy path. Replace both duplicated ordinary-move bonus/status blocks with `move_effects.apply_move_bonus(...)`, which keeps the file below 300 lines.

- [ ] **Step 7: Add the test to the aggregate runner and verify**

Add the test to `tools/run-godot-tests.sh`, then run:

```sh
./tools/godot-safe.sh --headless --script res://tests/combat/combat_move_effects_test.gd
./tools/godot-safe.sh --headless --script res://tests/combat_alignment_test.gd
./tools/check_file_size.sh
```

Expected: all PASS; file-size gate reports every project source at or below 500 and manual `wc -l scripts/combat_system.gd` reports no more than 300.

- [ ] **Step 8: Commit Task 3**

```sh
git add scripts/combat/combat_move_effects.gd scripts/game_state.gd scripts/combat_system.gd scripts/combat/combat_rules.gd scripts/skills/skill_loadout.gd tests/combat/combat_move_effects_test.gd tools/run-godot-tests.sh
git commit -m "feat: support reusable combat move effects"
```

---

### Task 4: Execute All Four Ultimate Ability Families

**Files:**
- Modify: `scripts/combat/ultimate_actions.gd`
- Create: `tests/combat/ultimate_abilities_integration_test.gd`
- Modify: `tools/run-godot-tests.sh`

**Interfaces:**
- Consumes: standard ultimate dictionaries from Task 2 and attack effects from `CombatAbilityRules.attack_effects`.
- Produces: player/NPC execution for `multi`, `abnormal`, `guaranteed_hit`, `drain_hp`, and `drain_mp`, retaining `ok`, `damage`, `landed`, and `ult` and adding `attempted` for deterministic multi-hit reporting.

- [ ] **Step 1: Write the integration test before changing the executor**

Create `ultimate_abilities_integration_test.gd` with the following harness and deterministic assertions:

```gdscript
extends SceneTree

const RULES := preload("res://scripts/combat/combat_ability_rules.gd")
const TEST_ENEMY_ID := "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"

var failures: Array[String] = []

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var state = root.get_node("GameState")
	var combat = root.get_node("CombatSystem")
	state.use_test_save_path("ultimate_abilities")
	state.delete_save()
	state.create_profile("绝招测试", {"strength": 25, "agility": 25, "constitution": 100, "wisdom": 25})
	state.profile.vitals.cultivation = 1000
	state.combat_state.mp = state.player_mp_max()
	state.combat_state.hp = state.player_effective_hp_max()
	_assert_true(RULES.multi_hits(30) == 3 and RULES.multi_hits(100) == 6, "连击边界")

	var abnormal_session := combat.create_session(TEST_ENEMY_ID, true)
	var abnormal := {"name": "测试异常", "abilities": ["abnormal"], "inner_level": 80, "inner_power": 0, "mp_cost": 0, "tier": 2}
	seed(101)
	combat.use_ult(abnormal_session, abnormal)
	_assert_true(abnormal_session.enemy_status.size() == 2, "80级异常绝招必须附加两种不同状态")
	for turns in abnormal_session.enemy_status.values():
		_assert_true(int(turns) == 2, "必定异常必须持续两回合")

	var hp_drain_session := combat.create_session(TEST_ENEMY_ID, true)
	state.combat_state.hp = maxi(1, int(hp_drain_session.player_max_hp) - 100)
	var hp_before := int(state.combat_state.hp)
	var hp_drain := {"name": "测试吸血", "abilities": ["guaranteed_hit", "drain_hp"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 1}
	seed(7)
	var hp_result := combat.use_ult(hp_drain_session, hp_drain)
	_assert_true(int(state.combat_state.hp) - hp_before <= int(floor(float(hp_result.damage) * 0.35)), "吸血不得超过实际伤害的35%")

	var mp_drain_session := combat.create_session(TEST_ENEMY_ID, true)
	mp_drain_session.enemy_mp = mp_drain_session.enemy_mp_max
	state.combat_state.mp = 0
	var mp_drain := {"name": "测试吸精", "abilities": ["guaranteed_hit", "drain_mp"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 2}
	seed(9)
	var enemy_mp_before := int(mp_drain_session.enemy_mp)
	combat.use_ult(mp_drain_session, mp_drain)
	var transferred := enemy_mp_before - int(mp_drain_session.enemy_mp)
	_assert_true(transferred <= int(floor(float(mp_drain_session.enemy_mp_max) * 0.15)) and transferred == int(state.combat_state.mp), "吸精必须按目标最大精力转移并守恒")

	var guaranteed := {"name": "测试必中", "abilities": ["guaranteed_hit"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 2}
	for index in 50:
		var guaranteed_session := combat.create_session(TEST_ENEMY_ID, true)
		guaranteed_session.enemy.attributes.agility = 100000
		var result := combat.use_ult(guaranteed_session, guaranteed)
		_assert_true(int(result.landed) == 1, "必中绝招第%d次不应落空" % index)

	var multi_session := combat.create_session(TEST_ENEMY_ID, true)
	multi_session.enemy_hp = 100000
	multi_session.enemy_max_hp = 100000
	var multi := {"name": "测试连击", "abilities": ["multi", "guaranteed_hit"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 2}
	seed(19)
	var multi_result := combat.use_ult(multi_session, multi)
	_assert_true(int(multi_result.attempted) == 6, "100级连击必须尝试6击")
	multi_session.enemy_hp = 1
	multi_session.enemy_max_hp = 1
	seed(23)
	var stopped_result := combat.use_ult(multi_session, multi)
	_assert_true(int(stopped_result.attempted) == 1, "目标倒下后必须停止后续连击")

	state.delete_save()
	print("ultimate_abilities_integration_test: PASS" if failures.is_empty() else "ultimate_abilities_integration_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: Run the new test and verify it fails**

```sh
./tools/godot-safe.sh --headless --script res://tests/combat/ultimate_abilities_integration_test.gd
```

Expected: FAIL because the old executor still branches on `kind` and does not apply ability arrays.

- [ ] **Step 3: Replace hard-coded type constants and dispatch with ability rules**

Preload `combat_ability_rules.gd`. In `_execute`, read `abilities`, and dispatch multi separately:

```gdscript
var abilities: Array = ult.get("abilities", [])
var level := int(ult.get("inner_level", 30))
var label := "施展【%s】" % ult.get("name", "绝招" if player_side else "敌方绝招")
var power_bonus := float(combat.rules.inner_power_attack_bonus(int(ult.get("inner_power", 0))))
if "multi" in abilities:
	return _execute_multi(session, ult, player_side, label, power_bonus, level)
return _execute_single(session, ult, player_side, label, power_bonus, abilities)
```

Use `ABILITY_RULES.multi_hits(level)` and `multi_power(level)` in `_execute_multi`.
Increment `attempted` immediately before each attack call and include it in the returned dictionary:

```gdscript
var attempted := 0
# inside the loop, after the target-down guard
attempted += 1
# result
return {"ok": true, "damage": total_damage, "landed": landed, "attempted": attempted, "ult": ult}
```

Compute `var attack_effects := ABILITY_RULES.attack_effects(ult)` once before the loop and pass it as the final `player_attack`/`enemy_attack` argument on every hit. This makes supported abilities genuinely composable and makes the guaranteed multi-hit stop test deterministic.

- [ ] **Step 4: Implement single-hit standard effects and guaranteed abnormal selection**

Build standard effects via `ABILITY_RULES.attack_effects(ult)` and pass them as the final argument to `combat.player_attack` / `enemy_attack`. After that call, if `"abnormal" in abilities`, apply statuses regardless of `hit`:

```gdscript
func _apply_abnormal(session: Dictionary, player_side: bool, inner_level: int) -> Array[String]:
	var pool: Array[String] = ["paralysis", "weakness", "poison"]
	pool.shuffle()
	var applied: Array[String] = []
	for index in ABILITY_RULES.abnormal_count(inner_level):
		var kind := pool[index]
		combat.add_status(session, "enemy" if player_side else "player", kind, 2)
		applied.append(kind)
	return applied
```

Append one authoritative log line listing the translated status names. Remove `_apply_paralysis`, `_reduce_target_max_hp`, old hit-bonus constants, and old reduce-max/huge-damage curves.

- [ ] **Step 5: Run integration, combat alignment, and state regressions**

Add the new test to `tools/run-godot-tests.sh`, then run:

```sh
./tools/godot-safe.sh --headless --script res://tests/combat/ultimate_abilities_integration_test.gd
./tools/godot-safe.sh --headless --script res://tests/combat_alignment_test.gd
./tools/godot-safe.sh --headless --script res://tests/combat_balance_test.gd
```

Expected: all PASS after replacing any old ultimate assertions with ability-based assertions. Existing ordinary-move status table assertions must remain unchanged.

- [ ] **Step 6: Commit Task 4**

```sh
git add scripts/combat/ultimate_actions.gd tests/combat/ultimate_abilities_integration_test.gd tests/combat_alignment_test.gd tools/run-godot-tests.sh
git commit -m "feat: execute composable ultimate abilities"
```

---

### Task 5: Truthful Battle Menu Labels

**Files:**
- Modify: `scripts/battle/battle_hud_renderer.gd`
- Modify: `tests/combat/ultimate_ability_rules_test.gd`

**Interfaces:**
- Consumes: standard ultimate dictionary fields `name`, `mp_cost`, `abilities`, and `inner_level`.
- Produces: `_format_ult_label(Dictionary) -> String` containing the same values used by runtime rules.

- [ ] **Step 1: Add failing label assertions**

Preload the renderer in `ultimate_ability_rules_test.gd`, instantiate it, and assert:

```gdscript
var renderer = preload("res://scripts/battle/battle_hud_renderer.gd").new()
var combo_label := renderer._format_ult_label({"name": "连击", "mp_cost": 25, "abilities": ["multi"], "inner_level": 100})
_assert_true(combo_label.contains("6击") and combo_label.contains("每击50%"), "连击菜单必须显示实际等级曲线")
var abnormal_label := renderer._format_ult_label({"name": "异常", "mp_cost": 30, "abilities": ["abnormal"], "inner_level": 80})
_assert_true(abnormal_label.contains("2种") and abnormal_label.contains("必定"), "异常菜单必须显示必定状态数量")
var hit_label := renderer._format_ult_label({"name": "必中", "mp_cost": 40, "abilities": ["guaranteed_hit"], "inner_level": 100})
_assert_true(hit_label.contains("必中") and hit_label.contains("200%"), "必中菜单必须显示实际倍率")
```

- [ ] **Step 2: Run the focused test and verify old labels fail**

Run the Task 1 test command.

Expected: FAIL because `_format_ult_label` still branches on old `kind` values.

- [ ] **Step 3: Format labels from the same ability rules**

Preload `combat_ability_rules.gd` in the renderer and replace `_format_ult_label` with an `abilities` match. Use the exact rule functions, for example:

```gdscript
if "multi" in abilities:
	return "%s  连击%d击（每击%d%%伤，独立判定）" % [name_cost, ABILITY_RULES.multi_hits(level), int(round(ABILITY_RULES.multi_power(level) * 100.0))]
if "abnormal" in abilities:
	return "%s  必定附加%d种异常（各2回合）" % [name_cost, ABILITY_RULES.abnormal_count(level)]
if "guaranteed_hit" in abilities:
	return "%s  必中，%d%%倍率伤害" % [name_cost, int(round(ABILITY_RULES.guaranteed_damage_scale(level) * 100.0))]
if "drain_hp" in abilities:
	return "%s  吸取实际伤害的%d%%体力" % [name_cost, int(round(ABILITY_RULES.drain_hp_ratio(level) * 100.0))]
if "drain_mp" in abilities:
	return "%s  吸取目标最大精力的%d%%" % [name_cost, int(round(ABILITY_RULES.drain_mp_ratio(level) * 100.0))]
```

- [ ] **Step 4: Run focused and HUD alignment tests**

```sh
./tools/godot-safe.sh --headless --script res://tests/combat/ultimate_ability_rules_test.gd
./tools/godot-safe.sh --headless --script res://tests/alignment_test.gd
```

Expected: both PASS. No protected HUD file is modified.

- [ ] **Step 5: Commit Task 5**

```sh
git add scripts/battle/battle_hud_renderer.gd tests/combat/ultimate_ability_rules_test.gd
git commit -m "fix: show runtime ultimate ability values"
```

---

### Task 6: Balance Documentation and Completion Audit

**Files:**
- Modify: `docs/balance_design.md`
- Modify: `docs/lore_bible.md`
- Verify: all files changed in Tasks 1–5

**Interfaces:**
- Consumes: verified runtime curves and behavior.
- Produces: documentation matching the authoritative GDScript implementation and fresh full-suite evidence.

- [ ] **Step 1: Update balance documentation with exact curves**

Replace the old four-type ultimate table/text in `docs/balance_design.md` with the 30/50/75/100 combo table, 1/2 guaranteed abnormal threshold, 1.5～2.0 guaranteed-hit curve, 20%～35% HP drain, and 8%～15% MP-max drain. Explicitly state that ordinary attack status procs at 20/40/50/70/80/90 remain unchanged.

- [ ] **Step 2: Update lore documentation without exposing obsolete mechanics**

In `docs/lore_bible.md`, describe the four sect allocations and state that guaranteed-hit and drain are reusable ordinary-move data effects. Remove references to reduce-max and old huge-damage ultimate types only; keep the ordinary-move status paragraph.

- [ ] **Step 3: Run JSON, diff, and file-size checks**

```sh
jq empty assets/Data/skills.json
git diff --check
./tools/check_file_size.sh
wc -l scripts/combat_system.gd scripts/combat/combat_ability_rules.gd scripts/combat/combat_move_effects.gd scripts/combat/ultimate_actions.gd
```

Expected: JSON and diff checks exit 0; all GDScript files are below 500, and each task-owned GDScript is no more than 300 lines.

- [ ] **Step 4: Run the complete safe regression suite**

```sh
./tools/run-godot-tests.sh
```

Expected: alignment, combat alignment, ability rules, move effects, ultimate integration, and combat balance tests all print `PASS` and the command exits 0. macOS CA-certificate and ObjectDB cleanup warnings are non-fatal only when every test reports PASS and exit status is 0.

- [ ] **Step 5: Audit every approved requirement against evidence**

Confirm from current files and test output:

- combo is 3–6 hits and level-scaled;
- abnormal applies 1–2 distinct statuses without a second proc roll;
- guaranteed hit bypasses misses/dodge but not parry and scales 1.5–2.0;
- HP drain uses actual HP loss;
- MP drain uses target max MP and conserves resources;
- ordinary moves can declare guaranteed-hit/damage/drain effects;
- existing ordinary-move random status mapping remains intact;
- player/NPC builders and executor paths are symmetric;
- HUD labels match runtime values;
- no save structure or protected file changed.

Any missing or indirect evidence means the task is not complete; add or strengthen the relevant focused test before proceeding.

- [ ] **Step 6: Commit documentation and final test adjustments**

```sh
git add docs/balance_design.md docs/lore_bible.md
git commit -m "docs: document composable ultimate abilities"
```
