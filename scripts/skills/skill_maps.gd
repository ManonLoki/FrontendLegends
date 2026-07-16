extends RefCounted
## 技能主题、基础功法与四维属性的共享映射表；全仓唯一权威来源，各系统一律引用此处。

const THEMES: Array[String] = ["code", "tune", "arch", "parry", "knowledge"]
const BASIC_SKILL_IDS: Array[String] = ["basicStrength", "basicAgility", "basicConstitution", "basicParry", "literacy"]
const THEME_BASIC_SKILL := {"code": "basicStrength", "tune": "basicAgility", "arch": "basicConstitution", "parry": "basicParry", "knowledge": "literacy"}
const THEME_COMBAT_KIND := {"code": "attack", "tune": "dodge", "parry": "parry"}
## 基础功法练至每 10 级为对应属性 +1；按参考项目设定 basicParry 反哺
## "strength" 而非 "agility"——招架练的是身法根基，故意与其他映射不对称。
## 存档规范化（GameState）与四维反哺（SkillSystem）必须互为逆运算，共用此表。
const BASIC_SKILL_ATTRIBUTE := {"basicStrength": "strength", "basicAgility": "agility", "basicConstitution": "constitution", "basicParry": "strength", "literacy": "wisdom"}
const ATTRIBUTE_LABELS := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}
