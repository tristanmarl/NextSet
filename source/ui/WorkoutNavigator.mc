import Toybox.Lang;
import Toybox.WatchUi;

// Workout menus and finish-flow entry points: the rest of the Navigator module (Monkey C merges
// declarations of a module across files). Split out of Navigator.mc.
module Navigator {
    // Key-only review of the finished workout (START saves, BACK opens Keep/Discard). With no
    // set logged START only says so; BACK still offers Discard.
    function review() as Void {
        if (getApp().controller().session() == null) {
            return;
        }
        WatchUi.pushView(new ReviewView(), new ReviewDelegate(), WatchUi.SLIDE_UP);
    }

    // Key-only Keep/Discard choice for the workout; Keep is selected first.
    function confirmDiscard(fromReview as Boolean) as Void {
        var view = new ConfirmView("Discard?", "Keep working", "Discard");
        WatchUi.pushView(view, new ConfirmDelegate(view, new DiscardWorkoutAction(fromReview)),
            WatchUi.SLIDE_UP);
    }

    function confirmUndo(entryId as String, slot as Number, view as ExerciseView,
                         fromOverview as Boolean) as Void {
        var confirmView = new ConfirmView("Delete set " + UiFormat.slotLabel(slot) + "?",
            "Cancel", "Delete");
        WatchUi.pushView(confirmView, new ConfirmDelegate(confirmView,
            new DeleteSetAction(entryId, slot, view, fromOverview)), WatchUi.SLIDE_UP);
    }

    function exerciseMenu(entryId as String, view as ExerciseView) as Void {
        exerciseMenuForEntry(entryId, view, false);
    }

    function exerciseMenuForEntry(entryId as String, view as ExerciseView,
                                  fromOverview as Boolean) as Void {
        var session = getApp().controller().session() as Dictionary;
        var exercise = UiFormat.exercise(session, entryId) as Dictionary;
        var title = exercise["name"] as String;
        var menu = new WatchUi.Menu2({:title=>title.length() > 18 ? title.substring(0, 16) + ".." : title});
        var next = SessionLogic.activeSlot(exercise);
        var lastEntry = SessionLogic.lastEditEntryId(session, entryId);
        if (next >= 0) {
            // First: the weight (or duration) of the next set in a one-field editor. Bodyweight
            // reps are changed on the set screen.
            var single = EditorLogic.singleField(exercise["loadType"] as String);
            if (single != null) {
                menu.addItem(new WatchUi.MenuItem(
                    Model.sameString(single, "durationSec") ? "Change time" : "Change weight",
                    UiFormat.draftLine(exercise, next), "edit_next", null));
            }
        }
        // Then the set logged last, with its values (in a superset possibly the other member's).
        if (lastEntry != null) {
            var lastExercise = UiFormat.exercise(session, lastEntry as String) as Dictionary;
            var lastSlot = UiFormat.lastSlot(lastExercise);
            var lastText = UiFormat.confirmText(lastExercise, lastSlot);
            menu.addItem(new WatchUi.MenuItem("Edit last set", lastText, "edit_last", null));
            menu.addItem(new WatchUi.MenuItem("Delete set " + UiFormat.slotLabel(lastSlot), null,
                "delete_last", null));
        }
        if (SessionLogic.nextWarmupSlot(exercise) >= 0) {
            menu.addItem(new WatchUi.MenuItem("Skip warmups", null, "skip_warmups", null));
        }
        if ((exercise["slots"] as Array).size() < Model.MAX_SETS &&
            SessionLogic.totals(session)["planned"] < Model.MAX_SETS_PER_WORKOUT) {
            menu.addItem(new WatchUi.MenuItem("Add set", null, "add_set", null));
        }
        var running = session["timedRun"] instanceof Dictionary;
        if (Model.sameString(exercise["loadType"], "timed") && next >= 0) {
            var draft = (Model.slotAt(exercise, next) as Dictionary)["draft"] as Dictionary;
            if (!running && draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0) {
                menu.addItem(new WatchUi.MenuItem("Log paused set",
                    draft["measuredSec"].toString() + " sec", "log_timed", null));
            }
        }
        var rest = session["rest"];
        if (!fromOverview && rest instanceof Dictionary &&
            Model.sameString(rest["state"], "running")) {
            menu.addItem(new WatchUi.MenuItem("Skip rest", null, "rest_skip", null));
        }
        if (next >= 0 && !running) {
            menu.addItem(new WatchUi.MenuItem("Skip exercise", null, "skip_today", null));
            // Swap when nothing is logged yet; otherwise add an alternative for the rest of the sets.
            menu.addItem(new WatchUi.MenuItem("Replace exercise", null,
                SessionLogic.completedCount(exercise) == 0 ? "swap_today" : "add_alt", null));
        }
        if (exercise["closedEarly"] == true) {
            menu.addItem(new WatchUi.MenuItem("Reopen exercise", null, "reopen", null));
        }
        menu.addItem(new WatchUi.MenuItem("Finish workout", null, "finish", null));
        WatchUi.pushView(menu, new ExerciseMenuDelegate(entryId, view, fromOverview), WatchUi.SLIDE_UP);
    }

    // After skipping: when nothing is left to do and a set is logged, offer to save the workout.
    function promptIfWorkoutDone() as Void {
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var exercises = (session as Dictionary)["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            if (SessionLogic.nextSlot(exercises[i] as Dictionary) >= 0) {
                return;
            }
        }
        if (SessionLogic.totals(session as Dictionary)["done"] > 0) {
            review();
        }
    }

    function activityResultActions() as Void {
        var menu = new WatchUi.Menu2({:title=>"Workout saved"});
        if (getApp().controller().canRetryActivitySave()) {
            menu.addItem(new WatchUi.MenuItem("Retry Garmin save", null, "retry", null));
        }
        menu.addItem(new WatchUi.MenuItem("Keep local log and exit", null, "exit", null));
        WatchUi.pushView(menu, new ActivityResultDelegate(), WatchUi.SLIDE_UP);
    }
}
