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

## 注入少量样式和属性：横屏锁定失败时，竖屏手机隐藏画布并显示旋转设备提示。
static func _apply_web_orientation(from_user_gesture: bool) -> void:
	if not _is_mobile_browser():
		return
	var gesture_flag := "true" if from_user_gesture else "false"
	var script := """
	(function () {
	  var isPortrait = window.matchMedia && window.matchMedia('(orientation: portrait)').matches;
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
  document.documentElement.setAttribute('data-frontend-landscape', '1');
  var style = document.getElementById('frontend-landscape-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'frontend-landscape-style';
    style.textContent = '@media (orientation: portrait) {' +
      'html[data-frontend-landscape="1"] body:after {' +
      'content:"请旋转设备至横屏"; position:fixed; inset:0; z-index:2147483647;' +
      'display:flex; align-items:center; justify-content:center; background:#000; color:#fff;' +
      'font-family:monospace; font-size:24px;' +
      '}' +
      'html[data-frontend-landscape="1"] canvas { visibility:hidden; }' +
      '}';
    document.head.appendChild(style);
  }
  if (%s && isPortrait && document.documentElement.requestFullscreen) {
    var fullscreen = document.documentElement.requestFullscreen();
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
""" % gesture_flag
	JavaScriptBridge.eval(script)

## 桌面浏览器也可能命中上述媒体查询，因此再按用户代理过滤，避免桌面端显示旋转提示。
static func _is_mobile_browser() -> bool:
	var user_agent := str(JavaScriptBridge.eval("navigator.userAgent || ''"))
	return user_agent.contains("Android") or user_agent.contains("iPhone") \
		or user_agent.contains("iPad") or user_agent.contains("Mobile")
