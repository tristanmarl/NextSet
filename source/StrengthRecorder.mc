import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Owns the recording and its FIT developer fields. Garmin Connect has no native set rows for a
// Connect IQ activity, so each logged set becomes one lap carrying the set as lap fields, and the
// session gets summary fields. Field ids match resources/fitcontributions.
// Limits (createField docs): apps get 256 bytes per message type; lap fields use 74 (name 65 incl.
// terminator, set 1, reps 2, weight 4, duration 2) and session fields 15.
// The firmware keeps one lap per second: a set logged in the same second as the previous lap is
// queued and written by flush() on a later tick.
// Any FitContributor failure is swallowed: logging a set must never depend on it.
class StrengthRecorder {
    private var _session as ActivityRecording.Session? = null;
    private var _nameField as FitContributor.Field? = null;
    private var _setField as FitContributor.Field? = null;
    private var _repsField as FitContributor.Field? = null;
    private var _weightField as FitContributor.Field? = null;
    private var _durationField as FitContributor.Field? = null;
    private var _totalSetsField as FitContributor.Field? = null;
    private var _volumeField as FitContributor.Field? = null;
    private var _exercisesField as FitContributor.Field? = null;
    private var _versionField as FitContributor.Field? = null;
    private var _pending as Array<Dictionary> = [] as Array<Dictionary>;
    private var _lastLapAt as Number = 0;

    public function start(name as String) as Boolean {
        if (_session != null) {
            return false;
        }
        try {
            _session = ActivityRecording.createSession({
                :name => name,
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
            });
            if (_session == null) {
                return false;
            }
            var session = _session as ActivityRecording.Session;
            createFields(session);
            if (session.start()) {
                return true;
            }
            session.discard();
            _session = null;
            return false;
        } catch (error) {
            _session = null;
            return false;
        }
    }

    // Fields belong to one Session, so they are created here for every new session (including a
    // new segment after an app restart) and never reused.
    private function createFields(session as ActivityRecording.Session) as Void {
        _nameField = null;
        _setField = null;
        _repsField = null;
        _weightField = null;
        _durationField = null;
        _totalSetsField = null;
        _volumeField = null;
        _exercisesField = null;
        _versionField = null;
        _pending = [] as Array<Dictionary>;
        _lastLapAt = 0;
        try {
            if (!(session has :createField)) {
                return;
            }
            var lap = FitContributor.MESG_TYPE_LAP;
            var summary = FitContributor.MESG_TYPE_SESSION;
            _nameField = session.createField("exercise", 0, FitContributor.DATA_TYPE_STRING,
                {:mesgType => lap, :count => 65});
            _setField = session.createField("set", 1, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => lap});
            _repsField = session.createField("reps", 2, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => lap});
            _weightField = session.createField("weight_kg", 3, FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => lap, :units => "kg"});
            _durationField = session.createField("duration_s", 4, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => lap, :units => "s"});
            _totalSetsField = session.createField("total_sets", 5, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => summary});
            _volumeField = session.createField("volume_kg", 6, FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => summary, :units => "kg"});
            _exercisesField = session.createField("exercises", 7, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => summary});
            _versionField = session.createField("nextset_version", 8, FitContributor.DATA_TYPE_STRING,
                {:mesgType => summary, :count => 8});
        } catch (error) {
            // Keep whatever was created; missing fields are skipped when writing.
        }
    }

    private function setLapFields(name as String, setNumber as Number, reps as Number,
                                  weightKg as Float, durationSec as Number) as Void {
        if (_nameField != null) {
            (_nameField as FitContributor.Field).setData(name);
        }
        if (_setField != null) {
            (_setField as FitContributor.Field).setData(setNumber);
        }
        if (_repsField != null) {
            (_repsField as FitContributor.Field).setData(reps);
        }
        if (_weightField != null) {
            (_weightField as FitContributor.Field).setData(weightKg);
        }
        if (_durationField != null) {
            (_durationField as FitContributor.Field).setData(durationSec);
        }
    }

    // One lap per logged set. The firmware writes at most one lap per second, so a set logged in
    // the same second as the previous lap is queued and written by flush() on the next tick.
    // Do not clear fields immediately after addLap(): setData() can replace a value before the
    // device writes it to FIT.
    public function recordSet(payload as Dictionary?) as Void {
        if (payload == null || !isRecording()) {
            return;
        }
        _pending.add(payload as Dictionary);
        flush();
    }

    // Writes the oldest queued set once the clock has moved past the last lap's second.
    public function flush() as Void {
        if (_pending.size() == 0 || !isRecording() || Time.now().value() <= _lastLapAt) {
            return;
        }
        writeLap(_pending[0]);
        _pending = _pending.slice(1, null) as Array<Dictionary>;
    }

    private function writeLap(payload as Dictionary) as Void {
        try {
            setLapFields(payload["name"] as String, payload["set"] as Number,
                payload["reps"] as Number, payload["weightKg"] as Float,
                payload["durationSec"] as Number);
            (_session as ActivityRecording.Session).addLap();
            _lastLapAt = Time.now().value();
        } catch (error) {
        }
    }

    private function setSummaryFields(summary as Dictionary?) as Void {
        if (summary == null) {
            return;
        }
        try {
            if (_totalSetsField != null) {
                (_totalSetsField as FitContributor.Field).setData(summary["sets"]);
            }
            if (_volumeField != null) {
                (_volumeField as FitContributor.Field).setData(summary["volumeKg"]);
            }
            if (_exercisesField != null) {
                (_exercisesField as FitContributor.Field).setData(summary["exercises"]);
            }
            if (_versionField != null) {
                (_versionField as FitContributor.Field).setData(
                    WatchUi.loadResource($.Rez.Strings.AppVersion) as String);
            }
        } catch (error) {
        }
    }

    public function isRecording() as Boolean {
        return _session != null && (_session as ActivityRecording.Session).isRecording();
    }

    public function pause() as Boolean {
        if (_session == null) {
            return false;
        }
        var session = _session as ActivityRecording.Session;
        return !session.isRecording() || session.stop();
    }

    public function resume() as Boolean {
        if (_session == null) {
            return false;
        }
        var session = _session as ActivityRecording.Session;
        return session.isRecording() || session.start();
    }

    public function hasSession() as Boolean {
        return _session != null;
    }

    public function save(summary as Dictionary?) as Boolean {
        if (_session == null) {
            return false;
        }
        try {
            var session = _session as ActivityRecording.Session;
            setSummaryFields(summary);
            // Best effort: anything still queued goes out now, even in the same second.
            while (_pending.size() > 0 && session.isRecording()) {
                writeLap(_pending[0]);
                _pending = _pending.slice(1, null) as Array<Dictionary>;
            }
            // stop() closes a final lap; blank its fields so it is not a copy of the last set.
            if (Time.now().value() > _lastLapAt) {
                setLapFields("", 0, 0, 0.0, 0);
            }
            if (session.isRecording() && !session.stop()) {
                return false;
            }
            if (!session.save()) {
                return false;
            }
            _session = null;
            return true;
        } catch (error) {
            return false;
        }
    }

    public function discard() as Boolean {
        if (_session == null) {
            return true;
        }
        _pending = [] as Array<Dictionary>;
        try {
            var session = _session as ActivityRecording.Session;
            if (session.isRecording() && !session.stop()) {
                return false;
            }
            if (!session.discard()) {
                return false;
            }
            _session = null;
            return true;
        } catch (error) {
            return false;
        }
    }
}
