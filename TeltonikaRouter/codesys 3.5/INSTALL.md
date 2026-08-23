# Installation

How to get the SMS alarm sender into a CODESYS project and running on a PLC.

Two routes: open the supplied project directly, or import the objects into an
existing project. The second is the usual case, since most plants already have
an application.

---

## 1. Prerequisites

| | |
|---|---|
| CODESYS | 3.5 SP21 or compatible |
| PLC | WAGO PFC300 (750-8302) or another PFC with a CODESYS V3 runtime |
| Device id | `1006 1300` |
| Device version | **6.4.5.11** |
| Router | Teltonika RUTX series, RutOS 7.x, reachable from the PLC over HTTPS |

### Finding the right device version

The Add Device dialog shows only the newest installed version by default. Tick
**"Display all versions (for experts only)"** at the bottom to see the rest.

If 6.4.5.11 is not listed at all, the device description is not installed.
Install it through **Tools → Device Repository → Install**, or through the WAGO
package in **Tools → Package Manager**. Installed descriptions live under
`C:\ProgramData\CODESYS\Devices\4096\1006 1300\`.

A newer description such as 6.4.6.10 also works, as long as it is not older than
the runtime on the PLC. Check the actual firmware in the router of the PLC web
interface under **Information → PLC Runtime**.

---

## 2. Libraries

Add these in the **Library Manager** before importing, so the imported code
compiles on the first attempt:

| Library | Used for |
|---|---|
| `WagoSysCurl` | `FbCurl`, the HTTPS client |
| `WagoAppTime` | `FuGetLocalDateAndTime` for the message timestamp |
| `Standard` | `TON`, `CONCAT`, `FIND`, `REPLACE`, `LEFT`, `MID`, `LEN` |

`WagoSysCurl` pulls in `WagoTypesCurl` and `WagoSysErrorBase` on its own.
Visualization libraries are added automatically when the first visualization is
imported.

On a WAGO template project for the PFC300 these are normally present already.

---

## 3. Import

In the target project: **Project → Import → Export file…** and select the
`.export` file.

If you are exporting from a working project instead, tick these objects:

- `prg_AlarmSMS`
- `FbAlarmSlot`
- `FbTeltonikaSMS` — the `ExtractJson` method follows automatically
- `GVL_TeltonikaCredentials`
- `AlarmMain`, `AlarmerListe`, `AlarmAlarms`

Nothing else is referenced.

**Device, tasks and library references do not travel with an object export.**
They are set up in the next steps.

---

## 4. Task configuration

Add `prg_AlarmSMS` to a cyclic task.

| Setting | Value |
|---|---|
| Type | Cyclic |
| Interval | **200 – 1000 ms** |
| Priority | 15 |
| Watchdog | Off, or generous |

### Why the interval matters

The send sequence advances **one step per task call**. A first message takes
eight steps; a follow-up message with a cached token takes two.

| Interval | First message | Follow-up |
|---|---|---|
| 1000 ms | about 8 s | about 2 s |
| 200 ms | about 1.6 s | under 1 s |

Below 200 ms there is nothing to gain, because each network round trip to the
router takes its own time regardless.

### It does not need its own task

`FbCurl` is asynchronous — `curl_easy_perform()` starts the transfer and returns
immediately, so nothing blocks. Putting `prg_AlarmSMS` in an existing cyclic
task is fine as long as that task runs at 1000 ms or faster. A dedicated task is
only worth it if you want to tune its interval independently.

**Never call `prg_AlarmSMS` from two tasks.** The same instance driven at two
rates produces half-finished requests and values that jump.

---

## 5. Visualization

1. **Visualization Manager → Add → WebVisu**
2. Set **Start visualization** to `AlarmMain`
3. Leave **Name of .htm file** as `webvisu`

The alarm table in `AlarmAlarms` is twenty **Frame** elements, each showing
`AlarmerListe`. Every frame needs two references:

```
alarm → prg_AlarmSMS.aAlarm[n]
iNr   → n
```

with `n` counting 1 to 20. If several rows show the same text, a frame is still
pointing at `aAlarm[1]` — check the **Element List** tab, where all frames and
their references are visible in one table.

### Reaching the WebVisu

`http://<plc-ip>/webvisu/webvisu.htm`

If the page hangs on *Loading Webvisualization*:

- **Is the application running?** A stopped application never answers. Press F5
  in CODESYS.
- **Port authentication.** Under **Ports and Services → PLC Runtime Services**,
  *Port Authentication enabled* makes the WebVisu require a login. Either turn it
  off, or add a user under Visualization Manager → User Management.

---

## 6. Router setup

The API is enabled by default on RutOS 7.x. What matters is the account.

1. The user must have **API access**. A low privilege user is rejected with
   `HTTP 401 code 120` — indistinguishable from a wrong password in the reply.
2. Verify from a shell **on the PLC**, so the test uses the same network path as
   the PLC code:

```sh
curl -sk -X POST "https://<router-host>/api/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"<user>","password":"<password>"}'
```

A token in the reply means the account is good. A 401 means it is not, and no
amount of PLC configuration will help.

The `busybox/sendsms_busyboxV3` script in this repository runs the whole flow
from the PLC shell and is the fastest way to separate a router problem from a
PLC problem.

---

## 7. Commissioning

In order:

1. Download and **start the application** (F5)
2. Enter the router host in `prg_AlarmSMS.sRouterOverride`
3. Enter the API user in `GVL_TeltonikaCredentials.Teltonika_Username`
4. Enter the password **online** in `GVL_TeltonikaCredentials.Teltonika_Password`
5. Set `sSiteName` to the plant name
6. Fill in `asRecipientNumber[1..4]` and tick `axRecipientEnable[]`
7. Leave `sModemIdForced` empty so the modem is detected automatically
8. Press the manual test with `sTestNumber` empty — it goes to every enabled
   recipient, exercising the same path a real alarm uses
9. Watch `uiSendStep` count 10 → 11 → 20 → 21 → 30 → 31
10. Configure the alarms: `sText`, `iDelaySec`, `axToRecipient[]`, then
    `xSmsEnable`
11. Wire the conditions: `prg_AlarmSMS.aAlarm[i].xAlarmIn := <your signal>`

### About the password

It is not stored in the project file, on purpose. Retain memory keeps it through
a restart, but **a download that changes any declaration clears retain**, and it
has to be entered again. `xCredentialsMissing` goes TRUE whenever the user name
or password is blank, and blocks sending rather than burning attempts.

If you do put the password in the source, remember that `$` is the escape
character in ST and must be written twice: `Pa$$word` becomes `'Pa$$$$word'`.
Characters such as `@` need no escaping.

---

## 8. Troubleshooting

| Symptom | Cause |
|---|---|
| `diHttpCode = 0`, `sCurlError` empty | The transfer had not finished. Should not happen — the block waits for `xDone`. |
| `diHttpCode = 0`, `sCurlError` filled in | No HTTP answer. DNS, TCP or TLS. Read the text. |
| `HTTP 401 code 120` | Wrong password, or the user has no API rights |
| `HTTP 422 Provided modem does not exist` | Modem id wrong. Clear `sModemIdForced` to auto-detect. |
| Nothing sends, `xCredentialsMissing` TRUE | Password blank — enter it online |
| Nothing sends, `xRateLimited` TRUE | Hourly ceiling reached, see `iMaxSmsPerHour` |
| Alarm never fires | `xSmsEnable` off, no recipient ticked in `axToRecipient[]`, or `iDelaySec` longer than you think |
| Every visu row shows the same alarm | Frame references all point at `aAlarm[1]` |
| Delay shows `300000` | Bound to `tOnDelay` with `%d`. Use `sDelayText` with `%s`. |

The value column in the CODESYS watch window truncates at about ten characters.
Widen it or use a watch list before concluding a string is wrong.

---

## 9. Notes for developers

Three CODESYS behaviours cost real time to find, and are worth knowing before
modifying this code:

- **`WagoSysCurl.FbCurl` is asynchronous.** `curl_easy_perform()` only starts
  the transfer. The FB body must be called every cycle for `xBusy`, `xDone` and
  `xError` to update. Reading the response code straight after `perform` always
  yields 0 and an empty buffer.
- **The standard string functions only see 255 characters.** `FIND`, `MID`,
  `LEFT` and `CONCAT` take `STRING(255)` parameters, so on a longer buffer they
  silently look at the beginning only. `ExtractJson` is a byte scanner for
  exactly this reason.
- **`r` cannot be used as a variable name.** `R` and `S` are reserved as IL
  operators, and `FOR r := 1 TO n DO` produces a cascade of unrelated-looking
  parser errors on one line.

And two visualization rules that shape the interface:

- A visualization can only write to `VAR_INPUT` and `VAR_IN_OUT`. That is why
  the delay is an `INT` in seconds rather than a `TIME`, and why the recipient
  selection is an array of `BOOL` rather than a bit mask.
- Use **checkboxes**, not radio buttons, for the recipient selection — radio
  buttons are mutually exclusive, and one alarm must be able to reach several
  people.
