# SMS alarm sender for WAGO PFC on a Teltonika router

A CODESYS 3.5 application that turns boolean alarm conditions in a PLC into SMS
messages, sent through the REST API of a **Teltonika RUTX** router. The router
holds the SIM card, so the PLC needs no modem of its own and no SMS subscription
beyond the one already in the router.

Developed and commissioned on a **WAGO PFC300 (750-8302)** against a
**RUTX09 running RutOS 7.x**, reached over a Tailscale tunnel.

## What it does

Twenty configurable alarm slots. Each slot watches one boolean, debounces it,
and sends a text message when it goes active — and optionally another when it
clears. Messages are queued, retried, and rate limited.

```
your signal ─► xAlarmIn ─► debounce ─► edge ─► queue ─► router ─► SMS
```

A typical message looks like:

```
Pumpehus 23.08 14:07 ALARM: Ventilasjonsaggregat 360.003 svarer ikke
```

Site name and timestamp are added automatically, so one phone can receive alarms
from several plants without confusion.

## Features

- **20 alarm slots**, each with its own text, delay and recipient selection
- **4 recipients**, individually enabled, freely assigned per alarm
- **Debounce per alarm** so a flickering signal or a brief network dropout does
  not wake anyone up
- **Message queue** so a burst of alarms is delivered one by one instead of
  overwriting each other
- **Rate limit** — a hard ceiling per rolling hour, protecting against a
  chattering signal turning into a phone bill
- **Retry with duplicate protection** — a failure that provably sent nothing is
  retried; one where the outcome is unknown never is
- **Token caching** — the router token is reused for four minutes, so a
  follow-up message costs one network round trip instead of three
- **Clear-message option** — send an OK when the fault goes away
- **Manual test** to a typed number or to the whole recipient list
- **WebVisu screens** for daily operation, the alarm table and the setup

## How it works

Three REST calls against the router:

| Step | Request | Result |
|---|---|---|
| 1 | `POST /api/login` | bearer token |
| 2 | `GET /api/modems/status` | modem id, for example `3-1` |
| 3 | `POST /api/messages/actions/send` | `success: true` |

Steps 1 and 2 are skipped while a cached token and a known modem id are still
valid, which is the normal case for anything but the first message.

The HTTP client is `WagoSysCurl.FbCurl`, which is **asynchronous**: each request
is split into a start step and a wait step, and the whole sequence advances one
step per task cycle. Nothing blocks the PLC task.

## Objects

| Object | Role |
|---|---|
| `prg_AlarmSMS` | Alarm engine: scans the slots, builds messages, owns the queue, retry and rate limit |
| `FbAlarmSlot` | One alarm: configuration plus debounce and edge detection |
| `FbTeltonikaSMS` | Router client, with the `ExtractJson` helper method |
| `GVL_TeltonikaCredentials` | Router host, user name and password |
| `AlarmMain` | Operator screen: status, counters, manual test |
| `AlarmerListe` | One alarm row, reused through a frame |
| `AlarmAlarms` | The alarm table, twenty frames referencing `AlarmerListe` |

Each alarm is a function block instance rather than a row across several
parallel arrays. That lets a visualization frame reference the whole alarm with
a single parameter, as recommended in the CODESYS *Best Practices Visualization*
document, section 1.6.

## Configuration

Everything an operator changes lives in `prg_AlarmSMS`, and every field is
writable from a visualization.

### Alarm table

`aAlarm : ARRAY[1..20] OF FbAlarmSlot`

| Field | Meaning |
|---|---|
| `xAlarmIn` | The raw condition. Write it from your own logic. |
| `xSmsEnable` | Is this alarm allowed to send at all? |
| `sText` | The wording placed in the message, up to 70 characters |
| `axToRecipient[1..4]` | One BOOL per person — who gets this alarm |
| `iDelaySec` | Debounce in **seconds**. 30 is thirty seconds, 300 is five minutes. |
| `xActive` | Debounced state, read only |
| `sDelayText` | The delay rendered for a screen, for example `5 min` |

Wire your own conditions in from anywhere in the project:

```iecst
prg_AlarmSMS.aAlarm[1].xAlarmIn := NOT xPriceDataValid;
prg_AlarmSMS.aAlarm[2].xAlarmIn := GVL_Solar.xCommError;
```

### Recipients

| Variable | Meaning |
|---|---|
| `axRecipientEnable[1..4]` | Is this person in service? |
| `asRecipientName[1..4]` | Display only, never sent |
| `asRecipientNumber[1..4]` | International format, for example `+47XXXXXXXX` |

A message is sent only when the person is enabled **and** the alarm is addressed
to them. That means one person can be taken out of service for a holiday without
editing twenty alarms.

### General settings

| Variable | Default | Meaning |
|---|---|---|
| `xSmsGlobalEnable` | TRUE | Master switch, stops everything when FALSE |
| `xSendOkMessages` | TRUE | Also send a message when an alarm clears |
| `sSiteName` | — | Prefix in every message |
| `iMaxSmsPerHour` | 15 | Hard ceiling per rolling hour |
| `tPauseBetweenSms` | 10 s | Gap between two messages |
| `tRetryDelay` | 60 s | Wait before repeating a failed message |
| `sRouterOverride` | — | Router host. Empty falls back to the GVL. |
| `sModemIdForced` | empty | Empty means auto-detect, which is normal |

## Status and diagnostics

| Variable | Meaning |
|---|---|
| `iQueueCount` | Messages waiting right now |
| `iEnabledCount` / `iActiveCount` | How many alarms are armed, how many are standing |
| `udiSentOk` | Messages the router confirmed |
| `udiSendFailed` | Given up on after all retries |
| `udiUncertain` | Outcome unknown, never retried to avoid duplicates |
| `udiDropped` | Never queued because the FIFO was full |
| `sSmsStatus` | Live progress text |
| `sLastError` | Why the last attempt failed |
| `uiSendStep` | 10/11 login, 20/21 modem lookup, 30/31 send |
| `diHttpCode` | HTTP status. **0 means no HTTP answer at all** |
| `sCurlError` | The libcurl reason — read this whenever `diHttpCode` is 0 |

When something fails, read `diHttpCode` first. A real status code means the
router answered and rejected something; a zero means the request never got that
far, and `sCurlError` names the actual cause.

## Router requirements

The API user must have **API access rights**. An ordinary low privilege user is
rejected with `HTTP 401 code 120` even when the password is correct — the reply
looks identical to a wrong password, which makes this easy to misdiagnose.
Verified working with the `admin` account.

Nothing else needs enabling on a stock RutOS 7.x device: the API is on by
default, and the self-signed certificate is accepted because certificate
verification is switched off in the client.

## Limitations

- Message text is capped at **140 characters**, which keeps the SMS to a single
  GSM message and the assembled JSON body inside the 255 characters CODESYS
  `CONCAT` can produce.
- Double quotes in alarm text are replaced with spaces, since they would
  terminate the JSON string early.
- The recipient list is fixed at four. Raising it means changing
  `MAX_RECIPIENTS` in `prg_AlarmSMS` and the array size in `FbAlarmSlot`
  together.
- The password is deliberately **not** stored in the project. It is entered
  online once and kept in retain memory. A download that changes declarations
  clears retain, so it has to be entered again.

## Installation

See [INSTALL.md](INSTALL.md).

## Related

The `bash/` and `busybox/` folders in this repository contain shell
implementations of the same API flow. `sendsms_busyboxV3.sh` is useful for
testing a router independently of the PLC code — if the script works and the PLC
does not, the fault is in the PLC configuration rather than the router.
