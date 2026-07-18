# AGENTS.md

## 项目

FrontendLegends 是一款使用 GDScript 编写的 Godot 4.7 2D 俯视角格子角色扮演游戏。

- 主项目：`project.godot`
- 场景：`scenes/splash.tscn`、`scenes/character_creation.tscn`、`scenes/game.tscn`
- 运行时代码：`scripts/*.gd`
- 数据：`assets/Data/*.json`
- 地图：`assets/Map/maps/LoreWorld/` 下的 Tiled TMX 文件
- 图块集：`assets/Map/tilesets/` 下的 Tiled TSX XML 文件
- 逻辑视口与地图相机：480×320；图块尺寸：16×16 像素

仓库中的 `.tsx` 文件是运行时必需的 Tiled XML 图块集定义。

## 运行与测试

使用 Godot 4.7 打开仓库根目录，或执行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --editor
```

## 架构

- `scripts/game.gd`：主场景协调、移动、交互、HUD 状态、地图切换和战斗展示
- `scripts/game_state.gd`：角色资料、存档、生存状态和游戏时钟
- `scripts/data_registry.gd`：JSON 注册表与地图发现
- `scripts/tiled_map_loader.gd`：运行时 TMX/TSX 解析与地图查询
- `scripts/tiled_map_renderer.gd`：运行时地图绘制
- `scripts/inventory_system.gd`：背包、装备、消耗品和交易
- `scripts/skill_system.gd`：技能、训练、门派和学习
- `scripts/quest_system.gd`：任务运行状态与动态目标
- `scripts/npc_system.gd`：人物注册表合并、精灵、击败状态和掉落
- `scripts/combat_system.gd`：战斗会话与公式
- `scripts/battle_resolve.gd`：战斗结算
- `scripts/game_battle_ui.gd`：由 `game.gd` 持有的战斗 HUD 展示层
- `scripts/ui_progress_meter.gd`：学习、练功和冥想 HUD 共用的进度条
- `scripts/virtual_controls.gd`：移动端屏幕方向键以及确认、取消按钮
- `scripts/mobile_orientation.gd`：原生移动端与移动网页横屏请求

自动加载单例在 `project.godot` 中注册。

## 规则

1. Godot 场景和 GDScript 运行时是实现行为的唯一事实来源。
2. 保留 TMX/TSX 文件及其相对路径；地图会在运行时直接加载它们。
3. 运行行为必须兼容 Godot 4.7 无界面模式。测试不得与正式游戏共用 `user://` 存档路径。
4. 不提交 `.godot/`；它是已忽略的生成目录。
5. `tools/` 下的 Node 脚本是独立数据与版本工具，不属于游戏运行时。
6. **冻结的启动、角色创建与 HUD 代码：** 未获得用户单独且明确的二次确认前，不得修改 `scenes/splash.tscn`、`scripts/splash.gd`、`scenes/character_creation.tscn`、`scripts/character_creation.gd`、`scripts/game_battle_ui.gd`、`scripts/ui_progress_meter.gd`，以及 `scripts/game.gd` 中的 HUD 面板与布局代码，即 HUD 的 `@onready` 节点引用、所有名称以 `_layout_` 开头的函数、`_build_detail_huds` 和 `_use_detail_hud`。用户首次提出修改这些文件不算确认。编辑前必须停止操作，列出准确的受保护文件和拟修改内容，再请求用户为该次修改解锁。只有用户在后续消息中明确同意才授权编辑。授权仅限所列文件和所列改动，且只生效一次；以后再次修改仍需重新确认。允许只读检查和测试这些文件。`scripts/game.gd` 中移动、战斗结算、存读档、生存时间、动画等非 HUD 逻辑不受此规则保护。规范副本见 `CLAUDE.md`。
7. **源码规模与模块化：** 项目自有源码应以不超过 300 个物理行为目标，绝对不得超过 500 行。文件接近 300 行时，应按内聚职责拆分到功能目录和多个命名明确的文件。不得通过压缩格式、一行多语句、生成式间接层或无关工具堆积规避限制。依赖应指向狭窄稳定的接口；模块内部保持高内聚，模块之间保持低耦合，并尽量避免共享可变状态。测试同样受 500 行硬限制，应按行为或子系统拆分。生成或第三方目录 `.godot/`、`android/build/`、`dist/`、`web/` 不计入。重构完成前必须运行 `tools/check_file_size.sh`。
8. **冻结的基础玩法不变量：** `docs/design_invariants.md` 中的学习与战斗基础逻辑未经用户单独且明确的二次确认不得修改。学习必须保持“潜能按灵感转换为固定口径学习经验 → 经验满 → 按实际潜能消耗支付 Token → 升级”；固定升级经验不得读取灵感。战斗必须保留四属性、已装备功法、装备和显式状态/阶位/AI 修正的共同作用及规定的核心结算阶段。允许在不改变资源身份、输入维度、职责和阶段顺序的前提下调整数值、系数、阈值、概率、曲线和计算公式。首次提出破坏不变量的修改不算确认；编辑前必须停止，列出准确不变量、文件、行为与数据/存档影响，再请求后续一次性解锁。规范副本见 `CLAUDE.md`。
