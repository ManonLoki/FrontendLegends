# FrontendLegends 项目文档

FrontendLegends 是一款使用 Godot 4.7 与 GDScript 开发的 2D 俯视角格子角色扮演游戏。游戏以现代前端技术生态构造江湖：角色属性对应工程能力，基础技能对应基本功，技术流派对应门派，高级技能与战斗招式则对应各门派的技术体系。

## 文档导航

- [世界与玩法设定集](lore_bible.md)：世界观、角色、门派、成长、战斗、任务、交易与时间规则。
- [代码与存档规范](code_and_save_standards.md)：中文注释、英文标识符、文件职责、存档 v3 与旧档迁移规则。
- [参照项目对齐审计](reference_alignment_audit.md)：当前项目与参照项目逐项核对后的结论及保留差异。
- 仓库根目录的 `AGENTS.md`：开发、测试、冻结文件和文件规模规则。
- 仓库根目录的 `CLAUDE.md`：与自动化开发工具共享的强制维护约束。

## 项目结构

| 路径 | 职责 |
| --- | --- |
| `project.godot` | Godot 项目配置、输入映射和自动加载单例注册 |
| `scenes/` | 启动画面、角色创建和主游戏场景 |
| `scripts/` | 游戏运行时、领域系统、界面与地图加载代码 |
| `assets/Data/` | 人物、物品、技能和任务的 JSON 数据 |
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

游戏设计分辨率为 640×480，地图瓦片尺寸为 16×16。桌面端使用键盘操作；移动端运行时会安装虚拟方向键和确认、取消按钮，并请求横屏显示。

## 自动加载单例

| 单例 | 主要职责 |
| --- | --- |
| `GameState` | 角色资料、存档、全局时钟、生存资源与战斗状态 |
| `DataRegistry` | JSON 数据注册、查询和地图发现 |
| `InventorySystem` | 背包、装备、消耗品和交易 |
| `SkillSystem` | 技能等级、学习、练功、冥想、装备与门派 |
| `QuestSystem` | 固定任务、环任务和动态目标 |
| `NpcSystem` | 人物数据合并、掉落和击败状态 |
| `CombatSystem` | 战斗会话、回合行为、状态和伤害公式 |
| `BattleResolve` | 胜负结算、奖励和战后伤势 |

## 数据权威顺序

1. Godot 场景与 GDScript 是运行行为的唯一实现事实。
2. `assets/Data/*.json` 是人物、技能、物品和任务内容的权威数据。
3. TMX 与 TSX 是地图、碰撞和地图对象的权威数据。
4. 本目录文档用于解释前三者，不得自行创造与实现不一致的规则。

## 存档

当前结构版本为 v3，仍沿用历史文件名 `user://frontend_legends_save_v2.json`，以便已有玩家无感升级。游戏可以读取 v2 存档，并把旧技能字段迁移为蛇形英文键；再次保存后写出 v3。装备状态按当前设计只存在于本局内存，不写入存档。

## 验证

修改运行时后至少执行：

```sh
./tools/check_file_size.sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/alignment_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/combat_alignment_test.gd
```

测试必须使用隔离的 `user://` 路径，不能污染正式存档。
