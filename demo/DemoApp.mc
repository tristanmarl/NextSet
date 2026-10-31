import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Screenshot build (monkey.demo.jungle, separate app id): fills the simulator with a made-up
// program, starts a workout with two logged sets and shows the main screens in turn, 8 s each,
// so they can be captured without button input. Never shipped.
class DemoApp extends NextSetApp {
    private var _cycle as Timer.Timer;
    private var _adder as Timer.Timer;
    private var _added as Number = 0;
    private var _screen as Number = 0;

    public function initialize() {
        Application.Storage.clearValues();
        seed();
        NextSetApp.initialize();
        _cycle = new Timer.Timer();
        _adder = new Timer.Timer();
    }

    // Seven planned sets show the "1/7" counter instead of dots; one set per tick (watchdog).
    public function addDemoSet() as Void {
        controller().addSet(demoEntry("Chest Press"));
        controller().skipWarmups(demoEntry("Chest Press"));
        _added++;
        if (_added >= 4) {
            _adder.stop();
        }
    }

    public function onStart(state as Dictionary?) as Void {
        var controller = controller();
        var now = Time.now().value();
        var routineId = controller.routineIds()[0] as String;
        if (controller.prepareWorkoutStart(routineId, now) && controller.reserveWorkoutStart() &&
            controller.commitWorkoutStart(now)) {
            var row = demoEntry("Seated Row");
            controller.completeDraft(row, Model.WARMUP_BASE, now);
            controller.completeDraft(row, 0, now);
            controller.completeDraft(row, 1, now);
        }
        NextSetApp.onStart(state);
        _cycle.start(method(:nextScreen), 8000, true);
        _adder.start(method(:addDemoSet), 700, true);
    }

    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new ExerciseView(demoEntry("Seated Row")), new WatchUi.BehaviorDelegate()];
    }

    public function nextScreen() as Void {
        _screen = (_screen + 1) % 11;
        var view = null;
        var row = demoEntry("Seated Row");
        var press = demoEntry("Chest Press");
        if (_screen == 0) {
            view = new ExerciseView(row);
        } else if (_screen == 1) {
            // Plain set screen (seven sets: counter); the rest is skipped for the next ones.
            controller().restAction("skip", Time.now().value());
            view = new ExerciseView(press);
        } else if (_screen == 2) {
            // "Change weight": the one-field editor, directly in EDIT.
            var exercise = UiFormat.exercise(controller().session() as Dictionary, press) as Dictionary;
            view = new SetEditView(press, SessionLogic.activeSlot(exercise), false, true);
        } else if (_screen == 3) {
            // "Edit last set": the two-level editor.
            var exercise = UiFormat.exercise(controller().session() as Dictionary, row) as Dictionary;
            view = new SetEditView(row, UiFormat.lastSlot(exercise), true, false);
        } else if (_screen == 4) {
            view = new ReviewView();
        } else if (_screen == 5) {
            view = new ConfirmView("Discard?", "Keep working", "Discard");
        } else if (_screen == 6) {
            var exercise = UiFormat.exercise(controller().session() as Dictionary, row) as Dictionary;
            var editor = new SetEditView(row, UiFormat.lastSlot(exercise), true, false);
            editor.startPressed();
            view = editor;
        } else if (_screen == 7) {
            view = new OverviewView();
        } else if (_screen == 8) {
            view = new SummaryView("completed");
        } else if (_screen == 9) {
            var history = new HistoryView();
            history.select();
            view = history;
        } else {
            view = new HomeView();
        }
        WatchUi.switchToView(view, new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    private function demoEntry(name as String) as String {
        var session = controller().session() as Dictionary;
        var exercises = session["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            if (Model.sameString((exercises[i] as Dictionary)["name"], name)) {
                return (exercises[i] as Dictionary)["entryId"] as String;
            }
        }
        return (exercises[0] as Dictionary)["entryId"] as String;
    }

    // Routines and config stored the way a routine sync leaves them.
    private function seed() as Void {
        var store = new Store();
        var dayA = Catalog.parseRoutine(WatchUi.loadResource(Rez.JsonData.DemoDayA), 1, 1) as Dictionary;
        var dayB = Catalog.parseRoutine(WatchUi.loadResource(Rez.JsonData.DemoDayB), 1, 2) as Dictionary;
        store.commitPair("routine." + (dayA["id"] as String), dayA);
        store.commitPair("routine." + (dayB["id"] as String), dayB);
        store.commitPair("config", {
            "schemaVersion" => 4,
            "nextSessionSeq" => 18,
            "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true},
            "incrementOverrides" => {},
            "routineIds" => [dayA["id"], dayB["id"]],
            "routineSyncSeq" => 1,
            "programId" => "demoprog",
            "programName" => "Full Body AB",
            "nextRoutineId" => dayA["id"]
        });
    }
}
