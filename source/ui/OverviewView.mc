import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class OverviewView extends WatchUi.View {
    private var _selectedIndex as Number = 0;
    private var _seenNextSetSequence as Number = 0;

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
        // Same positions as the set screen: name, set dots, heart rate.
        var h = dc.getHeight();
        UiFormat.drawTitle(dc, focusTitle, h * 25 / 100);
        var nextSlot = SessionLogic.nextSlot(focused);
        Icons.setDots(dc, h * 39 / 100, SessionLogic.completedCount(focused),
            focused["plannedSetCount"] as Number, nextSlot >= 0 && nextSlot < Model.WARMUP_BASE ? nextSlot : -1);
        UiFormat.drawHrRow(dc, h * 79 / 100, null);
        Icons.startMarker(dc, "play");
        Icons.backMarker(dc);
        Icons.browseMarkers(dc);
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

class OverviewDelegate extends WatchUi.BehaviorDelegate {
    private var _view as OverviewView;

    public function initialize(view as OverviewView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        if (Navigator.staleWorkoutView()) {
            return true;
        }
        var key = event.getKey();
        if (key == KEY_UP) {
            _view.moveSelection(-1);
            return true;
        }
        if (key == KEY_DOWN) {
            _view.moveSelection(1);
            return true;
        }
        if (key == KEY_ENTER) {
            _view.openSelection();
            return true;
        }
        return false;
    }

    public function onSelect() as Boolean {
        if (Navigator.staleWorkoutView()) {
            return true;
        }
        _view.openSelection();
        return true;
    }

    public function onMenu() as Boolean {
        if (Navigator.staleWorkoutView()) {
            return true;
        }
        Navigator.actions();
        return true;
    }

    public function onBack() as Boolean {
        return onMenu();
    }
}
