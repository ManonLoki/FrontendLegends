# 世界事件

世界事件统一维护在 `docs/data/world-events.xlsx` 的 `WorldEventTypes` 和 `WorldEvents` 工作表。`assets/Data/world_events.json` 是由该工作簿导出的运行时文件，不应手工维护。TMX 地图不再保存 `event`、`text` 或 `questGiver` 属性。

## 分层

- `WorldEventTypes`：以 UUID 定义可复用行为与默认参数；`action` 仍使用可读英文行为名。
- `WorldEvents`：定义稳定事件 ID、地图 ID、原型、触发格子和实例参数。
- TMX：只负责地形、道路、传送点、NPC，以及需要由 Tiled 绘制的纯视觉对象。
- `world_event_handler.gd`：解释 `action` 并执行游戏行为。

运行时由 `DataRegistry` 合并原型与实例参数，地图加载流程（`map_transition_controller.gd`）在解析 TMX 后调用 `TiledMapLoader.inject_objects` 把它们并入当前地图的对象查询；`TiledMapLoader` 本身保持纯 TMX 解析。因此寻路和交互仍使用同一套地图坐标接口。

## 新增事件

同类事件只需在 Excel 的 `WorldEvents` 添加一行：

| eventId | mapId | archetype | tileX | tileY | width | height | text |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| `<新 UUID>` | `<地图 UUID>` | `<事件原型 UUID>` | 12 | 8 | 1 | 1 | 前方东郊 |

- `eventId`、`mapId` 和 `archetype` 必须填写现有或新生成的 UUID；禁止用显示名或缩写代替。
- `tileX/tileY` 是触发矩形左上角的列和行。
- `width/height` 是触发范围的格数，单格事件均填 1。
- `displayName/text/questEndpoint` 只放该实例独有的数据，空白时继承原型默认值。

若事件有路牌、告示牌等独立图像，可继续在 TMX 放一个无事件属性的 `Props` 图块对象；它只负责显示。若图像已在 `Prop` 图层中，则 TMX 无需再放对象。

新增一种行为时，先在 `WorldEventTypes` 增加新的 `action`，再在 `scripts/game/interaction/world_event_handler.gd` 为该动作实现一次处理逻辑。已有同类实例无需复制脚本分支。

编辑完成后统一导出运行时 JSON：

```sh
npm run data:json -- --file=world_events
npm run data:ids:check
```

该命令只生成 `world_events.json`；不带 `--file` 时才会从六个工作簿生成全部运行时 JSON。禁止只复制某一张事件表或手工同步 JSON。

## 验证

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /tmp/frontend-legends-world-event-test.log --script res://tests/world_event_test.gd
tools/check_file_size.sh
```

专项测试会校验原型和摆放数量、关键事件注入结果，以及所有 TMX 都不再含旧事件属性。
