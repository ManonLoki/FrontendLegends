# FrontendLegends 文档

FrontendLegends 当前是 Godot 4.7 + GDScript 的 2D 格子 RPG。

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
