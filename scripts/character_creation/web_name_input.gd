extends RefCounted

## 微信等 WebView 不会为 Canvas 内的 LineEdit 稳定弹出输入法，因此通过真实 DOM input 中转。
static func available() -> bool:
	return OS.has_feature("web")

static func open(value: String) -> int:
	if not available():
		return -1
	var json_value := JSON.stringify(value)
	return int(JavaScriptBridge.eval(
		"window.FrontendNameInput ? window.FrontendNameInput.open(%s) : -1" % json_value,
	))

static func value() -> String:
	if not available():
		return ""
	return str(JavaScriptBridge.eval(
		"window.FrontendNameInput ? window.FrontendNameInput.value() : ''",
	))

static func submission() -> int:
	if not available():
		return -1
	return int(JavaScriptBridge.eval(
		"window.FrontendNameInput ? window.FrontendNameInput.submission() : -1",
	))

static func close() -> void:
	if available():
		JavaScriptBridge.eval(
			"if (window.FrontendNameInput) window.FrontendNameInput.close()",
		)
