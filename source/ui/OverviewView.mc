import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class OverviewView extends WatchUi.View {
    private var _selectedIndex as Number = 0;
    private var _seenNextSetSequence as Number = 0;
    private var _message as String? = null;

    public function initialize() {
        View.initialize();
        var session = getApp().controller().session();
        if (session != null) {
            var current = session as Dictionary;
            if (current["nextSetSequence"] instanceof Number) {
                _seenNextSetSequence = current["nextSetSequence"] as Number;
            }
            var exercises = (session as Dictionary)["exercises"] as Array;
            for (var i = 0; i < exercises.size(); i++) {
                if (SessionLogic.nextSlot(exercises[i] as Dictionary) >= 0) {
                    _selectedIndex = i;
                    break;
                }
            }
        }
    }

    public function onShow() as Void {
        getApp().overviewShown = true;
    }

    public function onHide() as Void {
        getApp().overviewShown = false;
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var session = getApp().controller().session();
        if (session == null) {
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL,
                "No active workout", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var current = session as Dictionary;
        var exercises = current["exercises"] as Array;
        if (exercises.size() == 0) {
            return;
        }
        if (current["nextSetSequence"] instanceof Number &&
            current["nextSetSequence"] != _seenNextSetSequence) {
            _seenNextSetSequence = current["nextSetSequence"] as Number;
            if (SessionLogic.nextSlot(exercises[_selectedIndex] as Dictionary) < 0) {
                for (var offset = 1; offset <= exercises.size(); offset++) {
                    var candidateIndex = (_selectedIndex + offset) % exercises.size();
                    if (SessionLogic.nextSlot(exercises[candidateIndex] as Dictionary) >= 0) {
                        _selectedIndex = candidateIndex;
                        break;
                    }
                }
            }
        }
        if (_selectedIndex >= exercises.size()) {
            _selectedIndex = 0;
        }
        var focused = exercises[_selectedIndex] as Dictionary;
        var focusTitle = focused["name"] as String;
        var groupLabel = SessionLogic.supersetLabel(current, _selectedIndex);
        if (groupLabel != null) {
            focusTitle = (groupLabel as String) + " " + focusTitle;
        }
        // Same positions as the set screen: name, a small row (position in the list), the sets
        // done big in the centre, the next set below it, heart rate.
        var h = dc.getHeight();
        UiFormat.drawTitle(dc, focusTitle, h * 25 / 100);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, h * 39 / 100, Graphics.FONT_SMALL,
            "Exercise " + (_selectedIndex + 1).toString() + "/" + exercises.size().toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // Small screens use the next smaller number font so the next-set line fits above the heart rate.
        var box = UiFormat.drawBigFrom(dc, [[SessionLogic.completedCount(focused).toString() + "/" +
            (focused["plannedSetCount"] as Number).toString(), "num"], ["sets", "unit"]],
            h * 55 / 100, -1, Graphics.COLOR_WHITE, h < 300 ? 1 : 0);
        var nextSlot = SessionLogic.activeSlot(focused);
        if (nextSlot >= 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            var captionY = box[3] - 2 + dc.getFontHeight(UiFormat.captionFont()) / 2;
            dc.drawText(dc.getWidth() / 2, captionY, UiFormat.captionFont(),
                (nextSlot >= Model.WARMUP_BASE ? "Warmup " : "") + UiFormat.draftLine(focused, nextSlot),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        }
        UiFormat.drawHrRow(dc, h * 79 / 100, _message);
        Icons.startMarker(dc, "play");
        Icons.backMarker(dc);
        Icons.browseMarkers(dc);
        Icons.addMarker(dc);
    }

    // Hold UP: one more working set for the selected exercise, a short buzz as feedback. A
    // refusal (set limit) or failed save shows a short error in the bottom row.
    public function addSet() as Void {
        var controller = getApp().controller();
        var session = controller.session();
        if (session == null) {
            return;
        }
        var exercises = (session as Dictionary)["exercises"] as Array;
        if (_selectedIndex >= exercises.size()) {
            return;
        }
        var entryId = (exercises[_selectedIndex] as Dictionary)["entryId"] as String;
        if (!SessionLogic.canAddSet(session as Dictionary, entryId)) {
            _message = "Max sets reached";
        } else if (controller.addSet(entryId)) {
            _message = null;
            getApp().buzz(false);
        } else {
            _message = "Could not add set";
        }
        WatchUi.requestUpdate();
    }

    public function moveSelection(direction as Number) as Void {
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var count = (session as Dictionary)["exercises"].size();
        if (count == 0) {
            return;
        }
        _selectedIndex = (_selectedIndex + direction + count) % count;
        _message = null;
        WatchUi.requestUpdate();
    }

    public function openSelection() as Void {
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var exercises = (session as Dictionary)["exercises"] as Array;
        if (_selectedIndex < exercises.size()) {
            Navigator.exercise((exercises[_selectedIndex] as Dictionary)["entryId"] as String);
        }
    }
}

class OverviewDelegate extends KeyDelegate {
    private var _view as OverviewView;

    public function initialize(view as OverviewView) {
        _view = view;
        KeyDelegate.initialize();
    }

    public function onUpKey() as Boolean {
        if (!Navigator.staleWorkoutView()) {
            _view.moveSelection(-1);
        }
        return true;
    }

    public function onDownKey() as Boolean {
        if (!Navigator.staleWorkoutView()) {
            _view.moveSelection(1);
        }
        return true;
    }

    public function onStartKey() as Boolean {
        if (!Navigator.staleWorkoutView()) {
            _view.openSelection();
        }
        return true;
    }

    public function onMenuKey() as Boolean {
        if (!Navigator.staleWorkoutView()) {
            _view.addSet();
        }
        return true;
    }

    public function onBackKey() as Boolean {
        if (!Navigator.staleWorkoutView()) {
            Navigator.review();
        }
        return true;
    }
}
