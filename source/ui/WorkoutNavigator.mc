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
