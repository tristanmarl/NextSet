import Toybox.Lang;
import Toybox.Test;

class UploadMemoryStore extends Store {
    private var _values as Dictionary = {};
    private var _failNextKey as String? = null;

    public function readKey(key as String) as Object? {
        return _values[key];
    }

    public function writeKey(key as String, value as Object) as Void {
        if (_failNextKey != null && Model.sameString(_failNextKey, key)) {
            _failNextKey = null;
            throw new Lang.Exception();
        }
        _values[key] = value;
    }

    public function deletePair(domain as String) as Void {
        _values.remove(domain + ".a");
        _values.remove(domain + ".b");
    }

    public function deleteUpload(id as String) as Void {
        deletePair("upload." + id);
    }

    public function failNextWrite(key as String) as Void {
        _failNextKey = key;
    }
}

function uploadStoreTestJob(sessionId as String) as Dictionary {
    var start = 1790752141;
    var end = 1790752201;
    return {
        "sessionId" => sessionId,
        "routine" => {"programId" => "fake-program", "week" => 1,
            "dayInWeek" => 1, "name" => "Fake Day"},
        "start" => start,
        "end" => end,
        "startTime" => start.toLong() * 1000,
        "endTime" => end.toLong() * 1000,
        "exercises" => [{
            "entryId" => "exercise-1",
            "liftosaurEntryId" => "lift-entry-1",
            "name" => "Fake Row",
            "loadType" => "weight",
            "unilateral" => false,
            "plannedSetCount" => 1,
            "sets" => [{"set" => 1, "reps" => 8, "kg" => 55.5,
                "timeSec" => null, "activeSec" => 20,
                "completedAt" => start + 40, "appendId" => null}]
        }],
        "substitutions" => [],
        "state" => "start",
        "lastError" => null
    };
}

function uploadStoreHasId(ids as Array, id as String) as Boolean {
    for (var i = 0; i < ids.size(); i++) {
        if (Model.sameString(ids[i], id)) {
            return true;
        }
    }
    return false;
}

(:test)
function testUploadStoreRecoveryAndRetirement(logger as Test.Logger) as Boolean {
    var retryStore = new UploadMemoryStore();
    var retryId = "retry-session";
    var retryJob = uploadStoreTestJob(retryId);
    var setsJob = uploadStoreTestJob("state-check");
    setsJob["state"] = "sets";
    setsJob["setsBody"] = {"sets" => [{"entryId" => "exercise-1", "setId" => "set-1",
        "completed" => {"reps" => 8, "weight" => "55.5kg"}}]};
    var finishJob = SessionLogic.copyDictionary(setsJob);
    finishJob["state"] = "finish";
    var doneJob = uploadStoreTestJob("done-check");
    doneJob["state"] = "done";
    var stateContractValid = Model.validUpload(retryJob) && Model.validUpload(setsJob) &&
        Model.validUpload(finishJob) && Model.validUpload(doneJob) &&
        retryJob["startTime"] instanceof Long && retryJob["endTime"] instanceof Long;
    var savedBeforeManifest = retryStore.saveUpload(retryJob) &&
        Model.validUpload(retryStore.loadUpload(retryId)) &&
        (retryStore.loadUploadQueue() as Array).size() == 0;
    retryStore.failNextWrite("uploadq.a");
    var manifestWriteFailed = !retryStore.saveUploadQueue([retryId]);
    var remainsRetryable = Model.validUpload(retryStore.loadUpload(retryId)) &&
        (retryStore.loadUploadQueue() as Array).size() == 0;
    var retrySucceeded = retryStore.saveUploadQueue([retryId]);
    var retriedJob = retryStore.loadUpload(retryId);
    var retryQueued = retrySucceeded &&
        uploadStoreHasId(retryStore.loadUploadQueue() as Array, retryId) &&
        retriedJob != null && Model.sameString((retriedJob as Dictionary)["state"], "start");

    var rotationStore = new UploadMemoryStore();
    var completedId = "completed-session";
    var completed = uploadStoreTestJob(completedId);
    completed["state"] = "done";
    var savedCompleted = rotationStore.saveUpload(completed) &&
        rotationStore.saveUploadQueue([completedId]);
    var removed = rotationStore.removeUploadFromQueue(completedId);
    var olderAfterRemoval = rotationStore.loadOlderPair("uploadq");
    var retainedJob = rotationStore.loadUpload(completedId);
    var preservedWhileOlderReferences = removed && olderAfterRemoval != null &&
        uploadStoreHasId((olderAfterRemoval as Dictionary)["ids"] as Array, completedId) &&
        retainedJob != null && Model.sameString((retainedJob as Dictionary)["state"], "done") &&
        !(uploadStoreHasId(rotationStore.loadUploadQueue() as Array, completedId));
    var rotated = rotationStore.saveUploadQueue([]);
    var latest = rotationStore.loadPair("uploadq");
    var older = rotationStore.loadOlderPair("uploadq");
    var reclaimedAfterRotation = rotated && rotationStore.loadUpload(completedId) == null &&
        latest != null && older != null &&
        !uploadStoreHasId((latest as Dictionary)["ids"] as Array, completedId) &&
        !uploadStoreHasId((older as Dictionary)["ids"] as Array, completedId);

    return check(logger, stateContractValid,
            "sanitized upload jobs validate in every durable state with exact epoch milliseconds") &&
        check(logger, savedBeforeManifest,
            "upload job is durable before the queue manifest references it") &&
        check(logger, manifestWriteFailed && remainsRetryable,
            "failed queue manifest write leaves the job intact and queue retryable") &&
        check(logger, retryQueued,
            "retry can add the already durable job to the queue") &&
        check(logger, savedCompleted && preservedWhileOlderReferences,
            "removal retains the completed job while the older queue generation still names it") &&
        check(logger, reclaimedAfterRotation,
            "a later queue rotation reclaims a job after neither generation references it");
}

(:test)
function testStoreValidatesEachGenerationOncePerLaunch(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var saved = store.commitPair("device", {"id" => "abc"});
    var first = store.loadPair("device");
    // Overwrite the same revision with an invalid payload: a cached read skips re-validation.
    store.writeKey("device.a", {"v" => 1, "rev" => 1, "payload" => {"id" => "NOT VALID"}});
    var cached = store.loadPair("device");
    var fresh = new UploadMemoryStore();
    fresh.writeKey("device.a", {"v" => 1, "rev" => 1, "payload" => {"id" => "NOT VALID"}});
    var uncached = fresh.loadPair("device");
    var committed = store.commitPair("device", {"id" => "next"});
    var after = store.loadPair("device");
    return check(logger, saved && first != null && Model.sameString(first["id"], "abc") &&
            cached != null && uncached == null && fresh.hasCorruptRecord(),
            "an unchanged generation is validated once; a new store validates it again") &&
        check(logger, committed && after != null && Model.sameString(after["id"], "next"),
            "a commit invalidates the cached generation and the newest revision wins");
}
