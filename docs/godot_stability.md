# Godot 稳定启动与崩溃处理

## 已确认的崩溃原因

Godot 4.7 在 macOS 或受限自动化环境中直接运行时，会尝试创建默认的 `user://logs`。如果该目录不可写，终端首先出现 `Failed to open 'user://logs/...'`，随后进程可能以 `signal 11` / `SIGSEGV` 崩溃。此故障发生在项目脚本执行之前，不代表游戏场景或 GDScript 自身崩溃。

## 固定解决方案

仓库内所有命令行启动、测试和自动化必须使用 `tools/godot-safe.sh`。该脚本固定项目根目录，并通过 `--log-file` 把每次运行的独立日志写入可写的 `/tmp/frontend-legends-godot-<进程号>.log`，避免触发默认日志目录故障。

```sh
# 打开编辑器
./tools/godot-safe.sh --editor

# 运行游戏
./tools/godot-safe.sh

# 运行全部 Godot 回归
npm run test:godot
```

通常不应直接执行 `/Applications/Godot.app/Contents/MacOS/Godot`。如需使用其他 Godot 二进制，可以只覆盖安全入口读取的 `GODOT_BIN`：

```sh
GODOT_BIN=/path/to/godot ./tools/godot-safe.sh --headless --quit
```

如需固定日志位置以便持续观察，可设置项目专用变量：

```sh
FRONTEND_LEGENDS_GODOT_LOG=/tmp/frontend-legends-debug.log ./tools/godot-safe.sh --editor
```

## 诊断边界

- 如果日志包含 `Failed to open 'user://logs/...'`，说明绕过了安全入口；改用 `tools/godot-safe.sh`。
- macOS 无界面测试中的系统 CA 证书警告不影响退出码，不能当作游戏崩溃。
- 如果安全入口仍以非零状态退出，保留脚本打印的日志路径，再根据日志中的首个 GDScript 错误或原生回溯定位；不能通过删除 `.godot/`、正式存档或项目数据来碰运气。
- 测试存档仍必须使用 `GameState.use_test_save_path(...)` 写入系统临时目录；安全日志不改变存档隔离规则。
