import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class SummaryView extends WatchUi.View {
    private var _outcome as String;

    public function initialize(outcome as String) {
        _outcome = outcome;
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var totals = SessionLogic.totals(session as Dictionary);
        var title = Model.sameString(_outcome, "completed") ? "Workout saved" : "Workout ended";
        var y = UiFormat.drawLine(dc, title, 80, Graphics.FONT_MEDIUM) + 8;
        y = UiFormat.drawLine(dc, totals["done"].toString() + "/" +
            totals["planned"].toString() + " sets", y, Graphics.FONT_LARGE) + 8;
        var caption = UiFormat.captionFont();
        if (session["elapsedSec"] instanceof Number && session["activeSec"] instanceof Number) {
            y = UiFormat.drawLine(dc, "ELAPSED " + duration(session["elapsedSec"] as Number),
                y, caption) + 6;
            y = UiFormat.drawLine(dc, "ACTIVE " + duration(session["activeSec"] as Number),
                y, caption) + 16;
        }
        UiFormat.drawLine(dc, "START: HOME", y, Graphics.FONT_XTINY);
    }

    private function duration(totalSeconds as Number) as String {
        var minutes = totalSeconds / 60;
        var seconds = totalSeconds % 60;
        return minutes.toString() + ":" + (seconds < 10 ? "0" : "") + seconds.toString();
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onSelect() as Boolean {
        Navigator.home();
        return true;
    }

    public function onBack() as Boolean {
        Navigator.home();
        return true;
    }
}
