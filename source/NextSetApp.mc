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
            startTimer(true);
        }
    }

    public function onStop(state as Dictionary?) as Void {
        stopTimer();
        AppBase.onStop(state);
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new HomeView(), new HomeDelegate()];
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
                Attention.vibrate([new Attention.VibeProfile(50, 500)]);
            } catch (error) {
            }
        }
        if (_controller.hasRunningRest() || _controller.hasRunningTimed() || vibrate) {
            WatchUi.requestUpdate();
        }
    }
}

class HomeView extends WatchUi.View {
    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var notice = getHomeNotice();
        var caption = UiFormat.captionFont();
        var totalHeight = dc.getFontHeight(Graphics.FONT_LARGE) + 8 +
            dc.getFontHeight(Graphics.FONT_TINY);
        if (notice != null) {
            totalHeight += 8 + dc.getFontHeight(caption);
        }
        var y = (dc.getHeight() - totalHeight) / 2;
        y = UiFormat.drawLine(dc, "NextSet", y, Graphics.FONT_LARGE) + 8;
        y = UiFormat.drawLine(dc,
            getApp().controller().hasRecoverySaveFailure() ? "START: Retry recovery" :
                (getApp().controller().hasPendingFinalization() ? "START: Retry save" :
                (getApp().controller().hasActiveSession() ? "START: Resume" : "START: Begin")),
            y, Graphics.FONT_TINY) + 8;
        if (notice != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            UiFormat.drawLine(dc, notice as String, y, caption);
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
}

function getApp() as NextSetApp {
    return Application.getApp() as NextSetApp;
}
