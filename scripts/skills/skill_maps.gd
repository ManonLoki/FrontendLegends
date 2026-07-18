extends RefCounted
## 技能主题、基础功法与四维属性的共享映射表；全仓唯一权威来源，各系统一律引用此处。

const THEMES: Array[String] = ["code", "tune", "arch", "parry", "knowledge"]
const BASIC_SKILL_IDS: Array[String] = ["2224675d-63f2-50e8-a2c6-064acd5c5623", "af088f07-4c52-5a8c-aa16-df96e6b3e056", "dcebef7e-09b8-5a69-8e3d-159cb2b0c355", "74903f7d-7f7f-52c2-a6da-b3f4b12b97f2", "1011d493-be02-53e2-86a2-a6a439328f84"]
const THEME_BASIC_SKILL := {"code": "2224675d-63f2-50e8-a2c6-064acd5c5623", "tune": "af088f07-4c52-5a8c-aa16-df96e6b3e056", "arch": "dcebef7e-09b8-5a69-8e3d-159cb2b0c355", "parry": "74903f7d-7f7f-52c2-a6da-b3f4b12b97f2", "knowledge": "1011d493-be02-53e2-86a2-a6a439328f84"}
const THEME_COMBAT_KIND := {"code": "attack", "tune": "dodge", "parry": "parry"}
## 四维各由一门对应基础功法反哺；基础招架已有直接战斗收益，不再额外叠加臂力。
## 存档规范化（GameState）与四维反哺（SkillSystem）必须互为逆运算，共用此表。
const BASIC_SKILL_ATTRIBUTE := {"2224675d-63f2-50e8-a2c6-064acd5c5623": "strength", "af088f07-4c52-5a8c-aa16-df96e6b3e056": "agility", "dcebef7e-09b8-5a69-8e3d-159cb2b0c355": "constitution", "1011d493-be02-53e2-86a2-a6a439328f84": "wisdom"}
const ATTRIBUTE_LABELS := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}
