# FrontendLegends 项目文档

FrontendLegends 是一款使用 Godot 4.7 与 GDScript 开发的 2D 俯视角格子角色扮演游戏。游戏以现代前端技术生态构造江湖：角色属性对应工程能力，基础技能对应基本功，技术流派对应门派，高级技能与战斗招式则对应各门派的技术体系。

## 文档导航

- [不可变设计规则](design_invariants.md)：冻结学习流程、战斗输入与修改授权边界；数值和公式可调，基础职责与阶段不可擅改。
- [世界与玩法设定集](lore_bible.md)：世界观、角色、门派、成长、战斗、任务、交易与时间规则。
- [v5 数值设计](balance_design.md)：数值目标、公式、人物分层、经济约束、模拟结果与设计依据。
- [师父学习经验与人物养成曲线](growth_curve_72h.md)：固定学习经验、潜能转换、Token 学费、阶段耗时和四维边界。
- [世界事件维护](world_events.md)：Excel 事件原型/摆放表、地图职责与 JSON 导出流程。
- [代码与存档规范](code_and_save_standards.md)：中文注释、英文标识符、UUID 规则、存档 v5 与版本边界。
- [参照项目差异审计](reference_alignment_audit.md)：当前实现从参照项目保留的语义与有意改变的数值。
- 仓库根目录的 `AGENTS.md`：开发、测试、冻结文件和文件规模规则。
- 仓库根目录的 `CLAUDE.md`：与自动化开发工具共享的强制维护约束。

## 项目结构

| 路径 | 职责 |
| --- | --- |
| `project.godot` | Godot 项目配置、输入映射和自动加载单例注册 |
| `scenes/` | 启动画面、角色创建和主游戏场景 |
| `scripts/` | 游戏运行时、领域系统、界面与地图加载代码 |
| `assets/Data/` | 六份 v5 运行时数据：人物、物品、技能、任务、世界事件和地图 UUID 索引 |
| `docs/data/items.xlsx`、`skills.xlsx`、`npcs.xlsx` | 道具、技能和 NPC 的独立维护工作簿；关联库存、教学、装备与掉落使用子表 |
| `docs/data/quests.xlsx`、`world-events.xlsx`、`maps.xlsx` | 任务、世界事件和地图索引的独立维护工作簿 |
| `docs/data/balance-rules.xlsx` | v5 数值目标、公式和约束参考，不直接导出运行时 JSON |
| `assets/Map/maps/LoreWorld/` | Tiled 制作的 TMX 世界地图 |
| `assets/Map/tilesets/` | 地图直接依赖的 TSX 瓦片集定义 |
| `tests/` | 领域、界面、菜单和战斗对齐测试 |
| `tools/` | 文件规模检查与数据表转换工具，不参与游戏运行 |

仓库中的 `.tsx` 文件是 Tiled XML 瓦片集，不是前端源代码，地图运行时会直接加载它们，不能删除或随意移动。

## 运行游戏

使用 Godot 4.7 打开仓库根目录，默认入口为 `scenes/splash.tscn`。也可以执行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --editor
```

游戏逻辑视口与地图相机统一为 480×320，地图瓦片尺寸为 16×16。Windows 与 macOS 默认窗口为 1280×960；桌面端使用键盘操作，移动端会安装虚拟方向键和确认、取消按钮，并请求横屏显示。

## 自动加载单例

| 单例 | 主要职责 |
| --- | --- |
| `DataRegistry` | JSON 数据注册、查询和地图发现 |
| `SkillSystem` | 技能等级、学习、练功、冥想、装备与门派 |
| `GameState` | 角色资料、存档、全局时钟、生存资源与战斗状态 |
| `InventorySystem` | 背包、装备、消耗品和交易 |
| `QuestSystem` | 固定任务、环任务和动态目标 |
| `NpcSystem` | 人物数据合并、掉落和击败状态 |
| `CombatSystem` | 战斗会话、回合行为、状态和伤害公式 |
| `BattleResolve` | 胜负结算、奖励和战后伤势 |

## 数据权威顺序

1. Godot 场景与 GDScript 是运行行为的唯一实现事实。
2. `assets/Data/*.json` 是人物、技能、物品、任务、世界事件和地图 UUID 索引的权威数据。
3. TMX 与 TSX 是地图、碰撞和地图对象的权威数据。
4. `docs/design_invariants.md` 定义学习与战斗的基础玩法契约；实现不得在没有用户后续明确确认时改变其中的资源身份、输入维度、职责或阶段顺序。
5. 其余文档用于解释前述事实与契约，不得自行创造与实现不一致的规则。

数值、系数、阈值与计算公式可以在保持不变量的前提下校准。若需求会触及不变量，首次提出不算授权：必须先列出准确文件、行为、存档/数据与测试影响，等待用户在后续消息中进行一次性明确解锁。

## 存档

当前结构版本为 v5，文件名为 `user://frontend_legends_save_v5.json`。资源主键已整体切换为 UUID，v2、v3、v4 存档全部作废且不会迁移。装备状态按当前设计只存在于本局内存，不写入存档。

## 验证

修改运行时后至少执行：

```sh
./tools/check_file_size.sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/alignment_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/combat_alignment_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/combat_balance_test.gd
```

测试必须使用 `GameState.use_test_save_path(...)` 写入系统临时目录，不能污染正式存档。数据表变更还必须执行 `npm run data:check`，校验 UUID 引用并确保六个独立工作簿覆盖的 JSON 往返不变。
