# UX review of the NextSet implementation plan

Reviewed 27 September 2026. This is a heuristic review of the proposed interactions, not a usability study or a device test. Findings below are addressed in `IMPLEMENTATION_PLAN.md`; remaining questions have explicit validation tasks.

## Main assessment

The product direction fits the gym context: an always-accessible overview, unrestricted exercise order, large current values, prior-performance context and physical-button operation. The original interaction proposal needed revision because it mixed set entry, correction and timer-driven navigation. Those modes would be difficult to distinguish while tired.

## Findings and changes

| Priority | Finding / user consequence | Revised plan |
|---|---|---|
| High | Rest expiry advanced the receipt to the next set. A rep edit at the deadline could target a different set than intended; users should not have to watch the timer to know what UP/DOWN means. | Rest expiry only updates the banner and vibrates. It never navigates or changes input targets. |
| High | A separate receipt required START to prepare the next set, including zero-rest work. “One START per set” was not consistently true. | Saving immediately presents the next draft with a nonmodal saved acknowledgment. Correction is explicit through Edit last set. |
| High | Showing the next draft immediately creates a rapid double-START risk. Pure slot idempotence does not prevent a second event from hitting the next slot. | Require button release and suppress activation for 800 ms after success; test rapid double presses on hardware. If insufficient, use an explicit ready action only after documenting the additional-press tradeoff. |
| High | A running timed set required a pause/cancel choice before another exercise could be logged. This contradicted flexible exercise switching. | BACK to overview checkpoints and pauses the timed measurement automatically, with visible feedback. Each slot retains paused elapsed time; returning can resume it. No modal blocker. |
| High | “Last,” “Today,” a saved receipt and a prefilled next set could all look like performed work. | Label “Next set n/N,” “Last time,” and “Saved #n.” Prefill never has a completed check mark. Correction editor names the completed slot. Test comprehension before/after logging. |
| Medium | “Abort,” “Finish” and “Exit” did not make retention/recovery effects clear. | Primary actions say Finish & save and Resume later. The abort path says End without updating last performance and explains that the local ended session remains. Garmin save/discard is a separate explicit choice. |
| Medium | A per-exercise Done check could hide skipped sets if early finishing counted as complete. | Closed early shows `k/N closed` with a distinct icon; only N/N gets the full-completion mark. Planned denominators stay fixed. |
| Medium | A 454×454 round screen cannot comfortably show the full textual example and eight overview rows using native readable fonts. | Three/four visible overview rows, two-line title, dominant actual-entry values, small context/banner, scrolling full previous detail. Verify long names and circle clipping on-device. |
| Medium | Corrections and next-load changes compete for the first menu item. Neither deserves a time-dependent shortcut. | Fixed menu: Edit last set, then Edit next load. Direct UP/DOWN always edits the displayed next draft. Prototype the two menu priorities and freeze the better one based on observed use. |
| Medium | Recoverable local progress could imply that Garmin recording and alarms also continue outside the app. | Resume screen separately labels local recovery and Garmin recording status. Resume later explains possible activity splitting. No promise of short-rest alarms after exit. |
| Medium | Structural workout creation is unavailable on-watch, limiting standalone use beyond the initial templates. | State this as an internal-MVP boundary. Numeric defaults remain editable; consumer template creation is deferred explicitly, not presented as completed functionality. |

## Remaining device/usability questions

1. Does held UP dispatch a short-UP event first? If so, direct rep editing must not cause an accidental increment when opening the menu. This is a platform gate, not a polish item.
2. Can users immediately tell that UP/DOWN now edits the displayed next draft, and find correction when needed? Test with real tasks, not a walkthrough.
3. Is MENU → Edit last set fast enough for frequent actual-versus-prefill corrections? Compare with adjusting reps before START; preserve post-save correction regardless.
4. Does automatically pausing timed work on BACK match expectation? The paused message and retained elapsed value must be obvious on return.
5. Are haptics reliable with the AMOLED screen off and system overlays present? Document actual firmware behavior.

## API level correction

Garmin currently lists the **Forerunner 965 at API level 5.2**. The earlier 4.2.0 value was a proposed minimum-compatibility baseline, not the watch's listed capability. For this FR965-only project, the revised plan uses **`minSdkVersion="5.2.0"`** throughout, including T001 and release acceptance. **SDK 9.2.0** is the compiler/toolchain version; it is a different version system. API level does not override individual API supported-device lists. [Garmin compatible devices](https://developer.garmin.com/connect-iq/compatible-devices/), [Garmin SDK](https://developer.garmin.com/connect-iq/sdk/)
