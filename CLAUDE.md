# CLAUDE.md

当前 Godot 项目架构、命令和仓库规则见 `AGENTS.md`。

## 强制冻结场景规则

未获得用户单独且明确的二次确认前，不得修改下列受保护文件：

- `scenes/splash.tscn`
- `scripts/splash.gd`
- `scenes/character_creation.tscn`
- `scripts/character_creation.gd`
- `scripts/game_battle_ui.gd`
- `scripts/ui_progress_meter.gd`
- `scripts/game.gd` 中的 HUD 面板与布局代码：HUD 的 `@onready` 节点引用、所有名称以 `_layout_` 开头的函数、`_build_detail_huds` 和 `_use_detail_hud`。此范围不包括世界或玩家绘制函数 `_draw()`，也不包括移动、战斗结算、存读档、生存时间、动画等其他非 HUD 逻辑。

用户首次要求修改受保护文件不算确认。编辑前必须停止操作，指出准确的受保护文件和拟修改内容，再请求用户为该次修改解锁。只有用户在后续消息中明确同意才授权编辑。确认只生效一次，并仅适用于已列出的文件和改动；以后每次修改受保护内容都需要新的二次确认。允许只读检查和测试。

## 源码规模与模块化

- 项目自有源码应以不超过 300 个物理行为目标，绝对不得超过 500 行。
- 功能增长时应在达到硬限制前按内聚职责拆分到清晰命名的目录和模块。
- 不得通过压缩格式、一行多语句、生成式间接层或把无关代码搬进通用工具文件来满足限制。
- 优先采用狭窄稳定的模块接口、模块内高内聚和模块间低耦合，并尽量避免共享可变状态。
- 测试同样受 500 行硬限制，应按子系统或行为拆分。
- 生成或第三方目录 `.godot/`、`android/build/`、`dist/`、`web/` 不计入。
- `tools/check_file_size.sh` 是仓库文件规模的权威检查命令。
