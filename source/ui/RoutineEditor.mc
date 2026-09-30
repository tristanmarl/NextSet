import Toybox.Lang;
import Toybox.WatchUi;

class RoutineListDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var itemId = item.getId() as String;
        if (Model.sameString(itemId, "empty")) {
            Navigator.syncRoutines();
        } else {
            Navigator.editTemplate(itemId);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
