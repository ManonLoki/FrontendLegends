extends RefCounted

## 原生移动端可通过 DisplayServer 强制横屏；移动网页会忽略该接口，
## 因此网页端改用 DOM 与全屏接口请求方向锁定。
const LANDSCAPE_ORIENTATION := DisplayServer.SCREEN_SENSOR_LANDSCAPE

static func apply() -> void:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(LANDSCAPE_ORIENTATION)
	if OS.has_feature("web"):
		_apply_web_orientation(false)

## 网页方向锁定只在全屏元素中生效，而浏览器仅允许真实点击或触摸进入全屏，
## 因此输入处理器必须再次调用此函数，不能只依赖启动时的被动设置。
static func request_from_user_gesture() -> void:
	if OS.has_feature("web"):
		_apply_web_orientation(true)

## 请求浏览器横屏；微信拒绝锁定时由 HTML 桥旋转画布并同步修正触摸坐标。
static func _apply_web_orientation(from_user_gesture: bool) -> void:
	if not _is_mobile_browser():
		return
	JavaScriptBridge.eval(_build_web_script(from_user_gesture))

## 单独生成脚本文本，使 CSS 百分号与手势标记可在非 Web 环境执行回归测试。
static func _build_web_script(from_user_gesture: bool) -> String:
	var gesture_flag := "true" if from_user_gesture else "false"
	var script := """
	(function () {
	  if (window.FrontendMobileOrientation) {
	    window.FrontendMobileOrientation.refresh();
	    if (__FROM_USER_GESTURE__) window.FrontendMobileOrientation.request();
	    return;
	  }
  var meta = document.querySelector('meta[name=screen-orientation]');
  if (!meta) {
	    meta = document.createElement('meta');
	    meta.name = 'screen-orientation';
	    document.head.appendChild(meta);
	  }
	  meta.content = 'landscape';
  if (window.screen && window.screen.orientation && window.screen.orientation.lock) {
	    var lock = window.screen.orientation.lock('landscape');
	    if (lock && lock.catch) { lock.catch(function () {}); }
	  }
	  if (__FROM_USER_GESTURE__) {
	    var fullscreenTarget = document.documentElement;
	    var requestFullscreen = fullscreenTarget.requestFullscreen || fullscreenTarget.webkitRequestFullscreen;
	    if (!requestFullscreen) { return; }
	    var fullscreen = requestFullscreen.call(fullscreenTarget);
    if (fullscreen && fullscreen.then) {
      fullscreen.then(function () {
        if (window.screen.orientation && window.screen.orientation.lock) {
          var retry = window.screen.orientation.lock('landscape');
          if (retry && retry.catch) { retry.catch(function () {}); }
        }
      }).catch(function () {});
    }
  }
})();
	"""
	script = script.replace("__FROM_USER_GESTURE__", gesture_flag)
	return script

## 仅移动浏览器需要请求横屏，桌面端保持普通响应式画布。
static func _is_mobile_browser() -> bool:
	var user_agent := str(JavaScriptBridge.eval("navigator.userAgent || ''"))
	return user_agent.contains("Android") or user_agent.contains("iPhone") \
		or user_agent.contains("iPad") or user_agent.contains("Mobile")
