import Toybox.Lang;

// Pure rules of the end-of-workout screen (Resume / Save / Discard) and of the summary's
// "Sync to Liftosaur" action. No UI, no storage.
module FinishLogic {
    const RESUME = 0;
    const SAVE = 1;
    const DISCARD = 2;
    const CHOICE_COUNT = 3;

    // What START does on a choice.
    const ACT_RESUME = "resume";
    const ACT_SAVE = "save";
    const ACT_NEED_SET = "need_set";
    const ACT_CONFIRM_DISCARD = "confirm_discard";

    function label(choice as Number) as String {
        if (choice == SAVE) {
            return "Save";
        }
        return choice == DISCARD ? "Discard" : "Resume";
    }

    // UP/DOWN move the selection and wrap around.
    function move(selected as Number, delta as Number) as Number {
        return (selected + delta + CHOICE_COUNT * 2) % CHOICE_COUNT;
    }

    // START on the selected choice. Save needs a logged set; Discard asks a second question.
    function actionFor(selected as Number, setsDone as Number) as String {
        if (selected == SAVE) {
            return setsDone > 0 ? ACT_SAVE : ACT_NEED_SET;
        }
        return selected == DISCARD ? ACT_CONFIRM_DISCARD : ACT_RESUME;
    }

    // BACK is never destructive: it resumes the workout.
    function backAction() as String {
        return ACT_RESUME;
    }
}
