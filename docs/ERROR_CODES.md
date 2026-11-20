# Error codes

Since 0.6.5, a failed Liftosaur request shows its code:

- **Settings → Test key**: "No response · CIQ -300" (a temporary problem, worth retrying) or "Request failed · HTTP 404" / "Request failed · CIQ -400" (anything else). A wrong key or missing Premium still reads "Key rejected", no phone connection "Phone not connected".
- **Home after a failed sync**: "Sync failed · CIQ -400". Temporary problems show "No response · will retry" instead and are retried automatically; -402 / -403 show "Liftosaur response too large; try later".
- **Settings → Diagnostics** keeps the code of the last failed sync request ("Last sync: Request failed: CIQ -400") until the next successful sync.

"HTTP n" is Liftosaur's answer. "CIQ n" comes from the watch or the Garmin Connect app on the phone: on Bluetooth the watch does not go online itself, Garmin Connect sends the request and passes the reply back. On a watch with Wi-Fi and the phone's Bluetooth off, the watch sends the request directly.

When reporting a problem, please include the message with its code, the line from Settings → Diagnostics, your watch model, and whether your phone is an iPhone or Android.

## Connect IQ codes

Did the request get there and back?

| Code | Garmin name | What it means |
|---|---|---|
| 0 | `UNKNOWN_ERROR` | Garmin gives no reason. |
| -1 | `BLE_ERROR` | Bluetooth problem between watch and phone. Retried. |
| -2 | `BLE_HOST_TIMEOUT` | The phone did not answer in time, often because Garmin Connect is asleep or restricted in the background. Retried. |
| -3 | `BLE_SERVER_TIMEOUT` | Timed out on the Bluetooth link. Retried. |
| -4 | `BLE_NO_DATA` | The phone answered with nothing. Retried. |
| -5 | `BLE_REQUEST_CANCELLED` | The Bluetooth request was cancelled. Retried. |
| -101 | `BLE_QUEUE_FULL` | Too many requests waiting, e.g. other apps or widgets syncing. Retried. |
| -102 | `BLE_REQUEST_TOO_LARGE` | NextSet sent too much. A NextSet bug. |
| -103 | `BLE_UNKNOWN_SEND_ERROR` | Sending over Bluetooth failed. Retried. |
| -104 | `BLE_CONNECTION_UNAVAILABLE` | No phone connection ("Phone not connected"). |
| -200, -201, -202 | `INVALID_HTTP_HEADER_FIELDS_IN_REQUEST`, `INVALID_HTTP_BODY_IN_REQUEST`, `INVALID_HTTP_METHOD_IN_REQUEST` | NextSet built a bad request. A NextSet bug. |
| -300 | `NETWORK_REQUEST_TIMED_OUT` | The phone got no answer from Liftosaur in time: slow network or server, or Garmin Connect has no internet access. Retried. |
| -400 | `INVALID_HTTP_BODY_IN_NETWORK_RESPONSE` | The answer arrived but could not be read as JSON: something in the account's data, the phone app's parser, or an HTML page instead of JSON. |
| -401 | `INVALID_HTTP_HEADER_FIELDS_IN_NETWORK_RESPONSE` | The answer's headers could not be read. |
| -402 | `NETWORK_RESPONSE_TOO_LARGE` | The answer is too big for the watch, e.g. a very large program or day. |
| -403 | `NETWORK_RESPONSE_OUT_OF_MEMORY` | The watch ran out of memory reading the answer. |
| -1000 | `STORAGE_FULL` | The watch's storage is full. |
| -1001 | `SECURE_CONNECTION_REQUIRED` | HTTPS problem; should not happen, NextSet always uses HTTPS. |
| -1002 | `UNSUPPORTED_CONTENT_TYPE_IN_RESPONSE` | The answer is not marked as JSON, probably an error or block page. |
| -1003 | `REQUEST_CANCELLED` | The system cancelled the request, e.g. the app was closed. Retried. |
| -1004 | `REQUEST_CONNECTION_DROPPED` | The connection broke during the request. Retried. |

## HTTP codes

What Liftosaur answered.

| Code | Liftosaur error | What it means |
|---|---|---|
| 401 | `unauthorized` | Wrong or missing key ("Key rejected"). |
| 403 | `subscription_required` | The account has no Premium ("Key rejected"). |
| 400, 422 | invalid request | Liftosaur does not accept what NextSet sent: a NextSet bug or an API change. |
| 404 | not found | During sync the normal end of the week; elsewhere no current program or an API change. |
| 409 | `workout_already_active` | Another workout is open in Liftosaur; the upload waits until it is finished. |
| 408 | timeout | Liftosaur was slow. Retried. |
| 429 | rate limited | Too many requests. Retried. |
| 5xx | server error | A problem at Liftosaur. Retried. |

"Retried" means sync and upload try again after 2, 5 and 10 minutes while the app is open, and on the next launch.
