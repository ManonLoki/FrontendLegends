extends RefCounted
## 对话分页、推进与关闭生命周期；布局仍由 Game HUD 负责。

var game: Node

# 处理init相关逻辑，并保持调用方状态一致。
func _init(owner: Node) -> void:
	game = owner

# 显示show相关逻辑，并保持调用方状态一致。
func show(speaker: String, text: String, lock_seconds: float = 0.0, after_last: Callable = Callable()) -> void:
	var clean_speaker := speaker.strip_edges()
	var clean_text := text.strip_edges()
	if clean_speaker.is_empty() and clean_text.is_empty():
		close()
		return
	game.dialogue_speaker = clean_speaker
	game.dialogue_after_last = after_last
	game.dialogue_locked_until_msec = Time.get_ticks_msec() + int(maxf(0.0, lock_seconds) * 1000.0)
	game.dialogue_pages = paginate(clean_text)
	game.dialogue_page_index = 0
	game.dialogue_auto_close_at_msec = 0
	if game.dialogue_pages.size() == 1 and not after_last.is_valid():
		game.dialogue_auto_close_at_msec = Time.get_ticks_msec() + game.DIALOGUE_AUTO_CLOSE_MSEC
	render(clean_speaker)
	game.dialogue_open = true
	game.dialogue_panel.visible = true

# 分页整理paginate相关逻辑，并保持调用方状态一致。
func paginate(text: String) -> Array[String]:
	var normalized := text.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n").replace("\r", "")
	var visual_lines: Array[String] = []
	for raw_line in normalized.split("\n", true):
		var line := str(raw_line)
		if line.is_empty():
			visual_lines.append("")
			continue
		while line.length() > 42:
			visual_lines.append(line.substr(0, 42))
			line = line.substr(42)
		visual_lines.append(line)
	return visual_lines if not visual_lines.is_empty() else [""]

# 渲染render相关逻辑，并保持调用方状态一致。
func render(speaker: String) -> void:
	var page: String = game.dialogue_pages[clampi(game.dialogue_page_index, 0, maxi(0, game.dialogue_pages.size() - 1))]
	game.dialogue_content.text = "%s:\n%s" % [speaker, page] if not speaker.is_empty() else page

# 推进advance相关逻辑，并保持调用方状态一致。
func advance() -> void:
	if game.dialogue_page_index < game.dialogue_pages.size() - 1:
		game.dialogue_page_index += 1
		game.dialogue_auto_close_at_msec = 0
		render(game.dialogue_speaker)
	elif game.dialogue_after_last.is_valid():
		var callback: Callable = game.dialogue_after_last
		game.dialogue_after_last = Callable()
		var followup := str(callback.call())
		if followup.strip_edges().is_empty():
			close()
		else:
			game.dialogue_pages = paginate(followup.strip_edges())
			game.dialogue_page_index = 0
			game.dialogue_locked_until_msec = 0
			game.dialogue_auto_close_at_msec = Time.get_ticks_msec() + game.DIALOGUE_AUTO_CLOSE_MSEC if game.dialogue_pages.size() == 1 else 0
			render(game.dialogue_speaker)
	else:
		close()

# 关闭close相关逻辑，并保持调用方状态一致。
func close() -> void:
	game.dialogue_open = false
	game.dialogue_speaker = ""
	game.dialogue_locked_until_msec = 0
	game.dialogue_auto_close_at_msec = 0
	game.dialogue_after_last = Callable()
	game.dialogue_pages.clear()
	game.dialogue_page_index = 0
	game.dialogue_panel.visible = false

# 更新auto、close相关逻辑，并保持调用方状态一致。
func update_auto_close() -> void:
	if game.dialogue_open and game.dialogue_auto_close_at_msec > 0 and Time.get_ticks_msec() >= game.dialogue_auto_close_at_msec:
		close()
