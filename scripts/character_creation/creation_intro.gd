extends RefCounted
## 角色创建开场字幕构建器；只负责静态节点和中文叙事文本，不持有输入状态。

const CONTENT_SIZE := Vector2(480.0, 320.0)
const COLOR_YELLOW := Color("#ffe678")
const COLOR_GRAY := Color("#b8b8b8")
const COLOR_WHITE := Color("#ffffff")

## 在设计舞台中创建裁剪容器和滚动内容，并返回主控制器需要持有的节点引用。
static func build(stage: Control, font: Font) -> Dictionary:
	var root := Control.new()
	root.name = "OpeningText"
	root.size = CONTENT_SIZE
	root.position = Vector2.ZERO
	root.clip_contents = true
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(root)
	var background := ColorRect.new()
	background.color = Color("#080a0e")
	background.size = CONTENT_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var content := Control.new()
	content.name = "ScrollingContent"
	content.size = CONTENT_SIZE
	root.add_child(content)
	var total_height := _append_lines(content, font)
	content.position = Vector2(0.0, CONTENT_SIZE.y + 34.0)
	return {"root": root, "content": content, "total_height": total_height}

## 依次创建字幕标签，并计算完整滚动内容高度。
static func _append_lines(content: Control, font: Font) -> float:
	var total_height := 0.0
	for line in _lines():
		var font_size := int(line[1])
		var label := _label(str(line[0]), font_size, line[2], font)
		var height := float(font_size) + 8.0
		label.position = Vector2(24.0, total_height)
		label.size = Vector2(432.0, height)
		content.add_child(label)
		total_height += height + float(line[3])
	return total_height

## 返回开场故事的“文字、字号、颜色、段后间距”数据。
static func _lines() -> Array:
	return [
		["18岁那年，高考结束", 17, COLOR_WHITE, 6],
		["你没有收到任何一所大学的录取通知书", 17, COLOR_WHITE, 18],
		["你试过外出打工，想靠双手把日子撑起来", 17, COLOR_WHITE, 6],
		["可简历石沉大海，面试屡屡碰壁，", 17, COLOR_WHITE, 6],
		["连最普通的岗位都像隔着一扇看不见的门", 17, COLOR_WHITE, 18],
		["后来，你不再投简历，也很少和家里说话", 17, COLOR_WHITE, 6],
		["白天昏睡，夜里醒来，", 17, COLOR_WHITE, 6],
		["把时间耗在网吧的泡面、游戏和通宵里", 17, COLOR_WHITE, 18],
		["直到今天清晨", 17, COLOR_GRAY, 18],
		["你刚从网吧出来，阳光刺得眼睛发疼", 17, COLOR_WHITE, 6],
		["一张皱巴巴的传单被风卷着，啪地拍在了你的脸上", 17, COLOR_WHITE, 18],
		["传单正中写着四个醒目的大字：", 17, COLOR_GRAY, 12],
		["码界招工", 24, COLOR_YELLOW, 18],
		["下方还有一行小字：", 17, COLOR_GRAY, 6],
		["诚招异界开发者，包吃包住，前途未知，风险自负", 17, COLOR_WHITE, 18],
		["也许是通宵后的脑子还不清醒，", 17, COLOR_WHITE, 6],
		["也许是你对原来的生活已经没什么留恋", 17, COLOR_WHITE, 6],
		["你拿起笔，在“乙方”那一栏填下了自己的名字", 17, COLOR_WHITE, 18],
		["下一秒，白光骤然亮起", 17, COLOR_YELLOW, 18],
		["等你再次睁开眼时，", 17, COLOR_WHITE, 6],
		["破旧的网吧、灰白的街道、催促你长大的世界，", 17, COLOR_WHITE, 6],
		["全都消失不见", 17, COLOR_WHITE, 18],
		["取而代之的，是一座陌生的小镇", 17, COLOR_WHITE, 6],
		["镇口的木牌上写着三个字：", 17, COLOR_GRAY, 12],
		["开源镇", 24, COLOR_YELLOW, 18],
		["而你的异界生活，也从这里正式开始", 17, COLOR_WHITE, 18],
		["若干年后", 17, COLOR_GRAY, 18],
		["也许你会站在顶峰，大喊我命由我不由天", 17, COLOR_WHITE, 18],
		["也许沉沦谷底，万般皆是命，半点不由人", 17, COLOR_WHITE, 18],
		["是非善恶，全凭一心", 17, COLOR_WHITE, 6],
	]

## 创建不拦截输入的统一字幕标签。
static func _label(text: String, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
