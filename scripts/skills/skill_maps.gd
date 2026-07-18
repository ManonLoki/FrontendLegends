extends RefCounted
## 技能主题、基础功法与四维属性的共享映射表；全仓唯一权威来源，各系统一律引用此处。

const THEMES: Array[String] = ["code", "tune", "arch", "parry", "knowledge"]
const BASIC_SKILL_IDS: Array[String] = ["basicStrength", "basicAgility", "basicConstitution", "basicParry", "literacy"]
const THEME_BASIC_SKILL := {"code": "basicStrength", "tune": "basicAgility", "arch": "basicConstitution", "parry": "basicParry", "knowledge": "literacy"}
const THEME_COMBAT_KIND := {"code": "attack", "tune": "dodge", "parry": "parry"}
## 四维各由一门对应基础功法反哺；基础招架已有直接战斗收益，不再额外叠加臂力。
## 存档规范化（GameState）与四维反哺（SkillSystem）必须互为逆运算，共用此表。
const BASIC_SKILL_ATTRIBUTE := {"basicStrength": "strength", "basicAgility": "agility", "basicConstitution": "constitution", "literacy": "wisdom"}
const ATTRIBUTE_LABELS := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}
