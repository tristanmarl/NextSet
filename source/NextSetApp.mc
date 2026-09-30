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
    // In-memory time of the last START-logged set; shared so the 800 ms guard survives view switches.
    private var _pendingKeyText as String? = null;
    private var _pendingKeySync as Boolean = false;
    public var lastSetSavedAt as Number? = null;

    public function initialize() {
        AppBase.initialize();
        _controller = new SessionController(new Store());
        _timer = new Timer.Timer();
        _startTimer = new Timer.Timer();
    }

    public function onStart(state as Dictionary?) as Void {
        AppBase.onStart(state);
        _controller.retryUploads();
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

    // Same pattern for the Liftosaur key; the text is handed over once and not kept.
    public function afterKeyEntry(text as String, autoSync as Boolean) as Void {
        _pendingKeyText = text;
        _pendingKeySync = autoSync;
        _startTimer.start(method(:runAfterKeyEntry), 250, false);
    }

    public function runAfterKeyEntry() as Void {
        var text = _pendingKeyText;
        _pendingKeyText = null;
        var problem = _controller.saveKey(text);
        if (problem == null && _pendingKeySync) {
            // Onboarding from Home: the stack is just Home, so no Settings refresh.
            _controller.syncRoutines();
            Navigator.feedback("Key saved · syncing");
            return;
        }
        Navigator.settings();
        Navigator.feedback(problem == null ? "Key saved" : problem as String);
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
            _controller.retryUploads();
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
        var code = _controller.errorCode();
        Navigator.home();
    }

    public function onTick() as Void {
        if (!_controller.isWorkoutRunning()) {
            stopTimer();
            return;
        }
        var vibrate = _controller.onTick(Time.now().value(), !_suppressFirstAlert);
        var preAlert = _controller.takePreRestAlert(Time.now().value(), !_suppressFirstAlert);
        _suppressFirstAlert = false;
        if (preAlert && _controller.vibrationEnabled() && Attention has :vibrate) {
            try {
                Attention.vibrate([new Attention.VibeProfile(100, 250)]);
            } catch (error) {
            }
        }
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

function getApp() as NextSetApp {
    return Application.getApp() as NextSetApp;
}
