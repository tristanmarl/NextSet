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
    private var _startTimer as Timer.Timer;
    private var _timerStarted as Boolean = false;
    private var _startPending as Boolean = false;
    private var _finishPending as Boolean = false;
    private var _startRoutineId as String? = null;
    private var _suppressFirstAlert as Boolean = false;

    public function initialize() {
        AppBase.initialize();
        _controller = new SessionController(new Store());
        _timer = new Timer.Timer();
        _startTimer = new Timer.Timer();
    }

    public function onStart(state as Dictionary?) as Void {
        AppBase.onStart(state);
        if (_controller.hasPendingFinalization()) {
            retryPendingFinalization();
        } else if (_controller.isWorkoutRunning()) {
            _controller.ensureRecordingSegment();
            startTimer(true);
        }
    }

    public function onStop(state as Dictionary?) as Void {
        if (_startPending) {
            _startTimer.stop();
            _controller.cancelWorkoutStart();
            _startPending = false;
            _startRoutineId = null;
        }
        _startTimer.stop();
        _finishPending = false;
        stopTimer();
        _controller.saveRecordingSegment();
        AppBase.onStop(state);
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        if (_controller.hasPendingFinalization()) {
            var progress = new FinishingWorkoutView();
            return [progress, new FinishingWorkoutDelegate()];
        }
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

    public function requestWorkoutStart(templateId as String) as Void {
        if (_startPending) {
            return;
        }
        _startPending = true;
        _startRoutineId = templateId;
        Navigator.startingWorkout();
        _startTimer.start(method(:prepareWorkoutStart), 150, false);
    }

    public function prepareWorkoutStart() as Void {
        if (!_startPending || _startRoutineId == null) {
            return;
        }
        if (!_controller.prepareWorkoutStart(_startRoutineId as String, Time.now().value())) {
            finishWorkoutStart(false);
            return;
        }
        _startTimer.start(method(:reserveWorkoutStart), 150, false);
    }

    public function reserveWorkoutStart() as Void {
        if (!_startPending) {
            return;
        }
        if (!_controller.reserveWorkoutStart()) {
            finishWorkoutStart(false);
            return;
        }
        _startTimer.start(method(:commitWorkoutStart), 150, false);
    }

    public function commitWorkoutStart() as Void {
        if (!_startPending) {
            return;
        }
        finishWorkoutStart(_controller.commitWorkoutStart(Time.now().value()));
    }

    public function requestWorkoutFinish(outcome as String) as Void {
        if (_finishPending || _startPending) {
            return;
        }
        if (_controller.hasPendingFinalization()) {
            retryPendingFinalization();
            return;
        }
        if (!_controller.finish(outcome, Time.now().value())) {
            var message = _controller.errorMessage();
            Navigator.feedback(message == null ? "Workout could not be finished" : message as String);
            return;
        }
        Navigator.finishingWorkout();
        retryPendingFinalization();
    }

    public function retryPendingFinalization() as Void {
        if (_finishPending || !_controller.retryFinalization()) {
            return;
        }
        _finishPending = true;
        _startTimer.start(method(:advanceFinalization), 150, false);
    }

    public function advanceFinalization() as Void {
        _finishPending = false;
        if (!_controller.hasPendingFinalization()) {
            return;
        }
        if (_controller.advanceFinalization()) {
            var session = _controller.session() as Dictionary;
            Navigator.finalized(session["status"] as String);
        } else if (_controller.errorMessage() == null) {
            retryPendingFinalization();
        } else {
            WatchUi.requestUpdate();
        }
    }

    private function finishWorkoutStart(succeeded as Boolean) as Void {
        var templateId = _startRoutineId;
        _startPending = false;
        _startRoutineId = null;
        if (succeeded) {
            startTimer(false);
            Navigator.overview();
            return;
        }
        _controller.cancelWorkoutStart();
        var error = _controller.errorMessage();
        if (templateId != null && Model.sameString(error, "Routine has no exercises")) {
            Navigator.editTemplate(templateId as String);
        } else {
            Navigator.home();
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
    private var _routines as Array = [];

    public function initialize() {
        View.initialize();
        _routines = getApp().controller().routineTemplates();
        if (_routines.size() == 0) {
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
        var routine = !active && _routineIndex >= 0 && _routineIndex < _routines.size() ?
            _routines[_routineIndex] as Dictionary : null;
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
            var entries = routine["entries"] as Array;
            var empty = entries.size() == 0;
            lines.add(routine["name"] as String);
            fonts.add(Graphics.FONT_MEDIUM);
            gaps.add(5);
            var totalSets = 0;
            for (var i = 0; i < entries.size(); i++) {
                totalSets += (entries[i] as Dictionary)["workingSetCount"] as Number;
            }
            lines.add(totalSets.toString() + " planned sets");
            fonts.add(caption);
            gaps.add(8);
            lines.add(empty ? "START: Add an exercise" : "UP/DOWN select · START begin");
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
        if (Model.sameString(error, "Routine not found")) {
            return "Routine not found";
        }
        if (Model.sameString(error, "Workout cannot start")) {
            return "Workout cannot start";
        }
        if (Model.sameString(error, "Could not reserve workout ID")) {
            return "Could not start workout";
        }
        if (Model.sameString(error, "Workout could not be created")) {
            return "Workout creation failed";
        }
        if (Model.sameString(error, "Activity recording failed to start")) {
            return "Recording failed to start";
        }
        if (Model.sameString(error, "Activity discard failed")) {
            return "Recording cleanup failed";
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
        var count = _routines.size();
        if (count > 0) {
            _routineIndex = (_routineIndex + direction + count) % count;
            WatchUi.requestUpdate();
        }
    }

    public function selectedTemplateId() as String? {
        return _routineIndex >= 0 && _routineIndex < _routines.size() ?
            (_routines[_routineIndex] as Dictionary)["id"] as String : null;
    }
}

class StartingWorkoutView extends WatchUi.View {
    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var y = (dc.getHeight() - dc.getFontHeight(Graphics.FONT_MEDIUM)) / 2;
        UiFormat.drawLine(dc, "Starting workout…", y, Graphics.FONT_MEDIUM);
    }
}

class FinishingWorkoutView extends WatchUi.View {
    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var error = getApp().controller().errorMessage();
        var message = error == null ? "Saving workout…" : error as String;
        var y = (dc.getHeight() - dc.getFontHeight(Graphics.FONT_SMALL)) / 2;
        UiFormat.drawLine(dc, message, y, Graphics.FONT_SMALL);
        if (error != null) {
            UiFormat.drawLine(dc, "SELECT TO RETRY", y + dc.getFontHeight(Graphics.FONT_SMALL),
                Graphics.FONT_XTINY);
        }
    }
}

class FinishingWorkoutDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        return true;
    }

    public function onSelect() as Boolean {
        if (getApp().controller().errorMessage() != null) {
            getApp().retryPendingFinalization();
        }
        return true;
    }

    public function onMenu() as Boolean {
        return onSelect();
    }

    public function onBack() as Boolean {
        return true;
    }
}

function getApp() as NextSetApp {
    return Application.getApp() as NextSetApp;
}
