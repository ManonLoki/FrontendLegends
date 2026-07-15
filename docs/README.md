# FrontendLegends 文档

FrontendLegends 当前版本为 **0.0.1**，是使用 Godot 4.7 + GDScript 制作的 2D 格子 RPG。

## 项目入口

- `project.godot`：Godot 项目配置与 Autoload 注册
- `scenes/`：启动、创角和游戏场景
- `scripts/`：全部游戏运行时代码
- `assets/Data/`：道具、技能、任务和 NPC 数据
- `assets/Map/maps/LoreWorld/`：Tiled TMX 地图
- `assets/Map/tilesets/`：Tiled TSX 瓦片集定义
- `tools/`：独立的数据表和版本转换工具

仓库中的 `.tsx` 是地图运行时必需的 Tiled XML tileset 文件。

## 运行

使用 Godot 4.7 打开仓库根目录。默认入口为 `scenes/splash.tscn`。

详细模块职责和维护规则见仓库根目录的 `AGENTS.md`。

## 玩家数据术语

- `cultivation`：玩家通过冥想获得的修为等级。每一级修为使战斗中的当前精力（MP）上限增加 2 点。
- `mp`：当前精力；冥想时会先填满它，再兑换为一个 `cultivation` 等级。它不是可持久累积的修为。
- `money`：Token 数量。
- `potential`：潜能数量，用于学习和训练。

新建角色的 Token、潜能与修为均从 0 开始。存档格式从 v1 升级为 v2；旧版存档不再读取。

世界观、门派和游戏术语见 [设定集](lore_bible.md)。
