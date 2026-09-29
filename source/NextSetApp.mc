import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class NextSetApp extends Application.AppBase {
    private var _controller as SessionController;
    private var _timer as Timer.Timer;
    private var _timerStarted as Boolean = false;
    private var _suppressFirstAlert as Boolean = false;

    public function initialize() {
        AppBase.initialize();
        _controller = new SessionController(new Store());
        _timer = new Timer.Timer();
    }

    public function onStart(state as Dictionary?) as Void {
        AppBase.onStart(state);
        if (_controller.isWorkoutRunning()) {
            _controller.ensureRecordingSegment();
            startTimer(true);
        }
    }

    public function onStop(state as Dictionary?) as Void {
        stopTimer();
        _controller.saveRecordingSegment();
        AppBase.onStop(state);
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new HomeView();
        return [view, new HomeDelegate(view)];
    }

    public function controller() as SessionController {
        return _controller;
    }

    public function startTimer(suppressFirstAlert as Boolean) as Void {
        if (_timerStarted || !_controller.isWorkoutRunning()) {
            return;
        }
        _suppressFirstAlert = suppressFirstAlert;
        _timer.start(method(:onTick), 1000, true);
        _timerStarted = true;
    }

    public function stopTimer() as Void {
        if (_timerStarted) {
            _timer.stop();
            _timerStarted = false;
        }
    }

    public function onTick() as Void {
        if (!_controller.isWorkoutRunning()) {
            stopTimer();
            return;
        }
        var vibrate = _controller.onTick(Time.now().value(), !_suppressFirstAlert);
        _suppressFirstAlert = false;
        if (vibrate && _controller.vibrationEnabled() && Attention has :vibrate) {
            try {
                Attention.vibrate([new Attention.VibeProfile(100, 1000)]);
            } catch (error) {
            }
        }
        if (_controller.hasRunningRest() || _controller.hasRunningTimed() || vibrate) {
            WatchUi.requestUpdate();
        }
    }
}

class HomeView extends WatchUi.View {
    private var _routineIndex as Number = 0;

    public function initialize() {
        View.initialize();
        var routines = getApp().controller().routineTemplates();
        if (routines.size() == 0) {
            _routineIndex = -1;
        }
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var controller = getApp().controller();
        var notice = getHomeNotice();
        var caption = UiFormat.captionFont();
        var active = controller.hasActiveSession();
        var routines = controller.routineTemplates();
        var routine = !active && _routineIndex >= 0 && _routineIndex < routines.size() ?
            routines[_routineIndex] as Dictionary : null;
        var lines = ["NextSet"];
        var fonts = [Graphics.FONT_LARGE];
        var gaps = [6];
        if (active) {
            var session = controller.session() as Dictionary;
            lines.add(controller.isWorkoutPaused() ? "WORKOUT PAUSED" : "WORKOUT ACTIVE");
            fonts.add(Graphics.FONT_SMALL);
            gaps.add(5);
            lines.add(session["templateName"] as String);
            fonts.add(caption);
            gaps.add(8);
            lines.add("START: Resume");
            fonts.add(Graphics.FONT_XTINY);
            gaps.add(8);
        } else if (routine != null) {
            lines.add(routine["name"] as String);
            fonts.add(Graphics.FONT_MEDIUM);
            gaps.add(5);
            lines.add(controller.templateTotalSets(routine["id"] as String).toString() +
                " planned sets");
            fonts.add(caption);
            gaps.add(8);
            lines.add("UP/DOWN select · START begin");
            fonts.add(Graphics.FONT_XTINY);
            gaps.add(8);
        } else {
            lines.add("Workout unavailable");
            fonts.add(Graphics.FONT_SMALL);
            gaps.add(8);
        }
        lines.add(active ? "MENU: Actions" : "MENU: History/Edit");
        fonts.add(caption);
        gaps.add(notice == null ? 0 : 4);
        if (notice != null) {
            lines.add(notice as String);
            fonts.add(caption);
            gaps.add(0);
        }
        var totalHeight = 0;
        for (var i = 0; i < lines.size(); i++) {
            totalHeight += dc.getFontHeight(fonts[i] as Graphics.FontType) +
                (gaps[i] as Number);
        }
        var y = (dc.getHeight() - totalHeight) / 2;
        for (var i = 0; i < lines.size(); i++) {
            if (notice != null && i == lines.size() - 1) {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            }
            y = UiFormat.drawLine(dc, lines[i] as String, y,
                fonts[i] as Graphics.FontType) + (gaps[i] as Number);
        }
    }

    private function getHomeNotice() as String? {
        var error = getApp().controller().errorMessage();
        if (Model.sameString(error, "Recovered earlier checkpoint")) {
            return "Recovered checkpoint";
        }
        if (Model.sameString(error, "Recovery save failed") ||
            Model.sameString(error, "Timed set recovery failed")) {
            return "Recovery save failed";
        }
        if (Model.sameString(error, "Save failed. Retry before continuing.")) {
            return "Save failed. Retry";
        }
        if (Model.sameString(error, "Saved workout is damaged")) {
            return "Workout data damaged";
        }
        if (Model.sameString(error, "Saved settings are damaged")) {
            return "Settings data damaged";
        }
        if (Model.sameString(error, "Update app to resume")) {
            return "Update app to resume";
        }
        if (Model.sameString(error, "Could not reserve workout ID")) {
            return "Could not start workout";
        }
        if (Model.sameString(error, "History save failed")) {
            return "History save failed";
        }
        if (Model.sameString(error, "Previous performance save failed")) {
            return "Last time save failed";
        }
        if (Model.sameString(error, "Workout archive saved; retry finish")) {
            return "Retry to finish";
        }
        if (Model.sameString(error, "Log a set before saving")) {
            return "Log one set first";
        }
        if (Model.sameString(error, "History needs newer app")) {
            return "Update app to save history";
        }
        return error == null ? null : "Check workout status";
    }

    public function moveRoutine(direction as Number) as Void {
        var count = getApp().controller().routineTemplates().size();
        if (count > 0) {
            _routineIndex = (_routineIndex + direction + count) % count;
            WatchUi.requestUpdate();
        }
    }

    public function selectedTemplateId() as String? {
        var routines = getApp().controller().routineTemplates();
        return _routineIndex >= 0 && _routineIndex < routines.size() ?
            (routines[_routineIndex] as Dictionary)["id"] as String : null;
    }
}

function getApp() as NextSetApp {
    return Application.getApp() as NextSetApp;
}
