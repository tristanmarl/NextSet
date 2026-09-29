import Toybox.ActivityRecording;
import Toybox.Lang;

class StrengthRecorder {
    private var _session as ActivityRecording.Session? = null;

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

    public function save() as Boolean {
        if (_session == null) {
            return false;
        }
        try {
            var session = _session as ActivityRecording.Session;
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
