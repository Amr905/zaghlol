# T-193 AC5 device run


## Warm (app in front)
- PASS: warm forged: no action, no token, backup route (started=1 probes=1)
- PASS: warm forged: action, no token, backup route (started=1 probes=1)
- PASS: warm forged: action, wrong token, backup route (started=1 probes=1)
- PASS: warm forged: token without the action (started=1 probes=1)
- PASS: warm forged: action, wrong token, mark-paid route, cancel id (started=1 probes=1)
- PASS: warm forged: action, no token, mark-paid route, cancel id (started=1 probes=1)
- PASS: forged start of the non-exported trampoline (refused: Starting: Intent { cmp=app.zaghlol.dev/app.zaghlol.platform.notifications.NotificationTapA)
- PASS: warm: nothing paid, no dialog (test checked the database) (in-process)

## Warm real taps
- PASS: real tap on the notification (warm) (open BackupTarget)
- PASS: tapped notification was cancelled (auto-cancel)
- PASS: real Mark-as-paid action then confirm (warm) (dialog, confirm, bill paid in the database)
- PASS: action notification was cancelled (cancel id)
- PASS: cold notifications posted (READY_COLD)
- PASS: in-process checks (database, dialog) (no PROBLEM line)
- PASS: cold notifications posted by the real app (9102=3 9104=2)

## Cold (process dead)
- PASS: cold forged: no action, no token, backup route (started=1 probes=1)
- PASS: cold forged: action, no token, backup route (started=1 probes=1)
- PASS: cold forged: action, wrong token, backup route (started=1 probes=1)
- PASS: cold forged: action, wrong token, mark-paid route, cancel id (started=1 probes=1)
- PASS: cold forged: action, no token, mark-paid route, cancel id (started=1 probes=1)
- PASS: cold forged: plain launch (no extras) (started=1 probes=1)

## Cold real taps
- PASS: real tap on the notification (cold) (NOTIF_PROBE launch route=false;NOTIF_PROBE open BackupTarget ctx=true;)
- PASS: real Mark-as-paid action then confirm (cold) (confirm shown, nothing paid before the tap, paid ok=true)

failed checks: 0
