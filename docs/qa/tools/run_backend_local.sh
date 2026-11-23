#!/bin/bash
# Passwords come from the environment (no literals in this file): QA_PG_SU_PW, QA_PG_MIGRATOR_PW, QA_PG_API_PW, QA_PG_ADMIN_PW.
# usage: be.sh <script-to-run-while-backend-is-up>   (starts PG + API, runs script, stops)
for v in QA_PG_SU_PW QA_PG_MIGRATOR_PW QA_PG_API_PW QA_PG_ADMIN_PW; do [ -n "${!v}" ] || { echo "set $v" >&2; exit 2; }; done
export PATH=$HOME/tc/dotnet:$PATH DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
PG=$HOME/tc/pg/bin; D=$HOME/tc/bedata; K=$HOME/tc/devkeys; R=$HOME/qa/repo/backend; PORT=55433
fresh=0
if [ ! -d $D ]; then fresh=1; $PG/initdb -D $D -U zaghlol -A md5 --pwfile=<(echo "$QA_PG_SU_PW") -E UTF8 >/dev/null; fi
$PG/pg_ctl -D $D -l $HOME/tc/be-pg.log -o "-p $PORT -k /tmp -c listen_addresses=127.0.0.1 -c log_error_verbosity=terse" -w start >/dev/null
export SU="host=127.0.0.1 port=$PORT user=zaghlol password=$QA_PG_SU_PW"
if [ $fresh = 1 ]; then
python3 - <<P
import psycopg,psycopg.sql,os
c=psycopg.connect(os.environ['SU']+' dbname=postgres',autocommit=True); c.execute('CREATE DATABASE zaghlol'); c.close()
c=psycopg.connect(os.environ['SU']+' dbname=zaghlol',autocommit=True)
c.execute(open('$R/deploy/db/bootstrap-roles.sql').read())
for r,e in [('migrator','QA_PG_MIGRATOR_PW'),('zaghlol_api','QA_PG_API_PW'),('zaghlol_admin','QA_PG_ADMIN_PW')]:
    c.execute('ALTER ROLE '+r+' PASSWORD '+psycopg.sql.Literal(os.environ[e]).as_string(c))
print('bootstrap ok')
P
ConnectionStrings__Migrator="Host=127.0.0.1;Port=$PORT;Database=zaghlol;Username=migrator;Password=$QA_PG_MIGRATOR_PW" dotnet $R/src/Zaghlol.Workers/bin/Release/net10.0/Zaghlol.Workers.dll --migrate 2>&1 | tail -3
fi
[ -f $K/kms.env ] || DEV_KEYS_DIR=$K sh $R/tools/dev-keys.sh
sed -i "s#Kms__Local__KeyDirectory=.*#Kms__Local__KeyDirectory=$K#" $K/kms.env
set -a
ASPNETCORE_ENVIRONMENT=Development; ASPNETCORE_URLS=http://127.0.0.1:8080
ConnectionStrings__App="Host=127.0.0.1;Port=$PORT;Database=zaghlol;Username=zaghlol_api;Password=$QA_PG_API_PW"
ConnectionStrings__Admin="Host=127.0.0.1;Port=$PORT;Database=zaghlol;Username=zaghlol_admin;Password=$QA_PG_ADMIN_PW"
Dev__KeyEnvFile=$K/kms.env; Dev__FakeStores=true
Purchases__Google__PackageName=app.zaghlol.dev; Purchases__Google__CredentialSource=None
Purchases__Google__Products__zaghlol_gold_monthly__Kind=subscription; Purchases__Google__Products__zaghlol_gold_monthly__Plan=monthly
Purchases__Google__Products__zaghlol_gold_yearly__Kind=subscription; Purchases__Google__Products__zaghlol_gold_yearly__Plan=yearly
Purchases__Google__Products__zaghlol_gold_lifetime__Kind=onetime; Purchases__Google__Products__zaghlol_gold_lifetime__Plan=lifetime
set +a
for kv in ${EXTRA_ENV:-}; do export "$kv"; done
(cd $R/src/Zaghlol.Api/bin/Release/net10.0 && exec dotnet Zaghlol.Api.dll) > $HOME/qa/out/api.log 2>&1 &
API=$!
for i in $(seq 1 40); do curl -s -o /dev/null -m 2 http://127.0.0.1:8080/v1/health && break; sleep 0.5; done
"$@"; rc=$?
kill $API 2>/dev/null; wait $API 2>/dev/null; echo "API exit code after SIGTERM: $?"
$PG/pg_ctl -D $D -m fast -w stop >/dev/null
exit $rc
