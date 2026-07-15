extends RefCounted
## 角色创建界面的无状态控件工厂，统一字体、颜色和输入穿透行为。

## 创建采用指定字体和颜色的文本标签。
static func label(text: String, font_size: int, color: Color, font: Font) -> Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_override("font", font)
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control

## 创建具有统一填充色和等宽边框的输入框样式。
static func field_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	return style
