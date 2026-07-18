# 数据工作簿

`assets/Data/*.json` 是 Godot 运行时读取的数据；本目录中的 Excel 是面向策划和内容维护的独立编辑入口。

| 工作簿 | 运行时输出 | 主要工作表 |
| --- | --- | --- |
| `items.xlsx` | `items.json` | `Items`、`VendorStock` |
| `skills.xlsx` | `skills.json` | `Skills`、`TeachStock` |
| `npcs.xlsx` | `npcs.json` | `NPCs`、技能、装备和掉落关系表 |
| `quests.xlsx` | `quests.json` | `Quests` |
| `world-events.xlsx` | `world_events.json` | `WorldEventTypes`、`WorldEvents` |
| `maps.xlsx` | `maps.json` | `Maps` |
| `balance-rules.xlsx` | 无 | `BalanceRules` 设计参考 |

## 维护流程

```sh
# 从全部工作簿导出六份运行时 JSON
npm run data:json

# 只导出一个领域，避免影响其他数据
npm run data:json -- --file=npcs

# 从当前 JSON 重建全部或单个工作簿
npm run data:excel
npm run data:excel -- --file=items

# 校验 UUID、跨表引用、TMX 地图引用和 Excel 往返一致性
npm run data:check
```

支持的 `--file` 值为 `items`、`skills`、`npcs`、`quests`、`world_events`、`maps`；`balance` 只用于重建规则参考表。

跨工作簿引用必须填写 UUID，不得填写显示名。`configJson` 保存未拆成普通列的复杂配置，必须保持为合法 JSON。

`FrontendLegendsData.xlsx` 是拆分前的历史快照，转换脚本不再读取它；保留该文件是为了不删除已有工作内容。
