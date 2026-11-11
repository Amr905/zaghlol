#!/usr/bin/env bash
# T-008 (Lead decision Q5): the SMS ingestion spike lives only in the devSms
# flavour. On a final APK this checks the merged manifest and the dex:
# - devSms: the SMS_RECEIVED receiver exists and requires BROADCAST_SMS
#   (only the telephony stack holds it), and the spike classes are present;
# - every other flavour: no SMS_RECEIVED receiver, no spike classes, no
#   WorkManager.
# Usage: check-sms-spike-placement.sh <aapt2> <apk> <flavor>
set -euo pipefail
AAPT2=$1
APK=$2
FLAVOR=$3
case "$FLAVOR" in devSms|devNoSms|stagingSms|stagingNoSms|prodSms|prodNoSms) ;; *) echo "::error::unexpected flavor"; exit 1 ;; esac
work=$(mktemp -d)
"$AAPT2" dump xmltree --file AndroidManifest.xml "$APK" > "$work/manifest.txt"
unzip -q -o "$APK" 'classes*.dex' -d "$work/dex"
ls "$work"/dex/classes*.dex > /dev/null || { echo "::error::no dex in $APK"; exit 1; }
# grep the files directly: `cat | grep -q` under pipefail fails with SIGPIPE
# when grep stops early, which would turn a hit into a miss.
dex_has() { grep -aqF "$1" "$work"/dex/classes*.dex; }

if grep -q 'android.provider.Telephony.SMS_RECEIVED' "$work/manifest.txt"; then has_rx=1; else has_rx=0; fi
if [ "$FLAVOR" = "devSms" ]; then
  [ "$has_rx" = 1 ] || { echo "::error::devSms has no SMS_RECEIVED receiver"; exit 1; }
  # The receiver element must carry permission=BROADCAST_SMS.
  awk '/E: receiver/{r=1; buf=""} r{buf=buf"\n"$0} /E: intent-filter/{if(r){print buf; r=0}}' "$work/manifest.txt" > "$work/receivers.txt"
  if ! grep -A20 'SpikeSmsReceiver' "$work/receivers.txt" | grep -q '"android.permission.BROADCAST_SMS"'; then
    echo "::error::devSms SMS receiver is not protected by BROADCAST_SMS"
    exit 1
  fi
  dex_has 'Lapp/zaghlol/spike/sms/SpikeSmsReceiver;' || { echo "::error::spike classes missing from devSms"; exit 1; }
  echo "devSms: receiver present and protected by BROADCAST_SMS"
else
  [ "$has_rx" = 0 ] || { echo "::error::$FLAVOR declares an SMS_RECEIVED receiver"; exit 1; }
  if dex_has 'Lapp/zaghlol/spike/'; then echo "::error::$FLAVOR contains spike classes"; exit 1; fi
  if dex_has 'Landroidx/work/'; then echo "::error::$FLAVOR contains WorkManager"; exit 1; fi
  echo "$FLAVOR: no SMS receiver, no spike classes, no WorkManager"
fi
