import Toybox.Lang;
import Toybox.WatchUi;

// Workout menus and finish-flow entry points: the rest of the Navigator module (Monkey C merges
// declarations of a module across files). Split out of Navigator.mc.
module Navigator {
    // End of the BACK chain: Resume / Save / Discard (Resume selected). With no set logged Save
    // only says so; Discard still works.
    function review() as Void {
        if (getApp().controller().session() == null) {
            return;
        }
        var view = new FinishChoiceView();
        WatchUi.pushView(view, new FinishChoiceDelegate(view), WatchUi.SLIDE_UP);
    }

    // Key-only Keep/Discard question; Keep is selected first. Keep returns to the workout.
    function confirmDiscard() as Void {
        var view = new ConfirmView("Discard workout?", "Keep", "Discard");
        WatchUi.pushView(view, new ConfirmDelegate(view, new DiscardWorkoutAction()),
            WatchUi.SLIDE_UP);
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
        if (getApp().controller().syncActionable()) {
            menu.addItem(new WatchUi.MenuItem("Sync to Liftosaur", null, "sync", null));
        }
        menu.addItem(new WatchUi.MenuItem("Keep local log and exit", null, "exit", null));
        WatchUi.pushView(menu, new ActivityResultDelegate(), WatchUi.SLIDE_UP);
    }
}
