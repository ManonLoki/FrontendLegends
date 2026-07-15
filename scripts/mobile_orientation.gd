extends RefCounted

## Native mobile export can force orientation directly via DisplayServer;
## mobile web browsers ignore that API, so orientation there has to be coaxed
## through the DOM/Fullscreen APIs instead (see _apply_web_orientation).
const LANDSCAPE_ORIENTATION := DisplayServer.SCREEN_SENSOR_LANDSCAPE

static func apply() -> void:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(LANDSCAPE_ORIENTATION)
	if OS.has_feature("web"):
		_apply_web_orientation(false)

## screen.orientation.lock() only works inside a Fullscreen Element, and browsers only grant
## fullscreen from a real user gesture (click/tap) — so this must be re-invoked from an
## input handler rather than relying on the passive apply() call above.
static func request_from_user_gesture() -> void:
	if OS.has_feature("web"):
		_apply_web_orientation(true)

## Injects a small inline stylesheet/attribute pair so a portrait-mode phone shows a
## "rotate your device" overlay and hides the canvas, since orientation lock can silently
## fail (unsupported browser, user gesture missing) and we still need a visible fallback.
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

## Desktop browsers also match some of the CSS media queries above; gate on the UA
## string so desktop players never see the "rotate your device" overlay.
static func _is_mobile_browser() -> bool:
	var user_agent := str(JavaScriptBridge.eval("navigator.userAgent || ''"))
	return user_agent.contains("Android") or user_agent.contains("iPhone") \
		or user_agent.contains("iPad") or user_agent.contains("Mobile")
