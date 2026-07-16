extends RefCounted
## HUD 控件通用工具。

## 同步释放数组中仍有效的控件并清空数组；各面板的临时控件清理共用此循环，
## 保证同一次状态刷新中不会短暂叠放旧节点和新节点。
static func free_all(widgets: Array) -> void:
	for widget in widgets:
		if is_instance_valid(widget):
			widget.free()
	widgets.clear()
