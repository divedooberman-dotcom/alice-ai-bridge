# Cherny skill application identity investigation

Investigation date: 2026-11-13. Read-only investigation; no deployment,
service restart or speaker command was performed during this investigation.

## Finding

Cherny's incoming skill application identity no longer matched its stored
automatic-reading binding. A factory reset and re-pairing on November 12 are
the most likely explanation, but the retained evidence does not establish
the exact cause or time of the identity change. A firmware installation also
occurred between the old and new observations.

The values below are eight-character prefixes of SHA-256 hashes, not raw
application identifiers or credentials.

## Evidence

- The A1 gateway's `voice_events` archive contains 92 requests with application
  hash prefix `c2d1469f`, from October 14 at 07:17:37 UTC through October 19 at
  07:01:31 UTC. Their skill hash matches Family AI and their client metadata
  identifies `Yandex cucumber`.
- The archive contains only those 92 events. Its last event is not evidence
  that the old identity stopped working on October 19.
- The November 12 operational record documents the user's factory reset and
  re-pairing, observation of factory firmware `.28`, and subsequent installation
  of stock Cucumber firmware `.46`.
- Retained A1 bridge journal entries show 11 received requests with the new
  origin prefix `e4559d02`, from November 13 at 03:40:27 UTC through 04:16:22 UTC.
  These are the retained observation boundaries, not the identity's creation
  time. No old-origin entries were found in the retained journal search.
- The earlier authorized pairing repair associated the new origin with
  Cherny. A subsequent Family AI launch succeeded. The registry now retains
  both old and new application hashes under Cherny's existing physical target.
- Provisioning had accepted an existing stored binding and a ready Glagol
  connection without verifying that current skill requests still matched that
  binding. This explains why provisioning missed the stale association.

## Interpretation and limits

Yandex documents `session.application.application_id` as the identity of an
application instance scoped to a skill, not as a permanent hardware serial
number. Reinitialization after a reset is consistent with that definition.
The documentation does not establish that every Station reset changes this
field or disclose the identity-generation algorithm.

There are no saved skill requests between the reset, re-pairing and firmware
installation that would isolate their effects. Accordingly, attributing the
change specifically to the reset remains an inference. The earlier categorical
claim that the reset caused the change should not be treated as proven.

The corrected binding was preserved when the later automatic-recovery release
was rolled back. This report does not authorize or recommend redeploying that
release and does not claim that future identity changes recover automatically.

Reference: [Yandex Dialogs request format, session.application](https://yandex.ru/dev/dialogs/alice/doc/ru/request#sessionapplication).
