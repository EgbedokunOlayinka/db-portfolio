#!/usr/bin/env bash
# Wavers University — Portfolio 5: replication, consistency and failover
#
#   bash portfolio-5-distributed-cloud/Olayinka_Egbedokun_reproduce.sh
#
# Starts a fresh primary and streaming replica (PostgreSQL 18.6), loads the
# Portfolio 1 schema and Portfolio 2 seed on the primary, runs scenarios
# 1-4, writes each log to evidence/ and checks every outcome; any other
# outcome stops the run. Every scenario changes the same record: the head of
# Computer Science corrects Zainab's CSC101 score, which changes her CGPA.

set -euo pipefail
cd "$(dirname "$0")/.."
P5=portfolio-5-distributed-cloud
E=$P5/evidence
mkdir -p "$E"
DC="docker compose -f $P5/compose.yml"
PRIMARY=wu-p5-primary
REPLICA=wu-p5-replica

sql() { docker exec -i "$1" psql -U wavers -X -v ON_ERROR_STOP=1 -d wavers "${@:2}"; }
val() { sql "$1" -tA -c "$2"; }
fail() { echo "CHECK FAILED: $*" >&2; exit 1; }
say() { echo "$*" >> "$F"; }
correct() { sql "$1" -v score="$2" -v mode="${3:-on}" < $P5/Olayinka_Egbedokun_correction.sql; }   # correct <server> <score> [mode]
until_true() {   # until_true <server> <query returning t/f> <what>: poll every 0.1 s for up to 10 s
  for _ in $(seq 100); do [ "$(val "$1" "$2")" = t ] && return 0; sleep 0.1; done
  fail "$3 (not within 10 s)"
}
caught_up() { until_true $REPLICA "SELECT pg_last_wal_replay_lsn() >= '$(val $PRIMARY "SELECT pg_current_wal_lsn()")'" "the replica did not catch up"; }
CGPA="SELECT cgpa FROM student_cgpa WHERE student_id = (SELECT student_id FROM students WHERE matric_no = 'WU/2023/0003')"
STATUS="SELECT application_name, state, sync_state FROM pg_stat_replication"

echo "Starting a fresh primary and replica..."
$DC down -v > /dev/null 2>&1 || true
$DC up -d --wait --quiet-pull > /dev/null 2>&1 || fail "could not start the primary and replica (is Docker running?)"
pinned=$(sed -n 's/^ *image: postgres:\([0-9.]*\) *$/\1/p' $P5/compose.yml | sort -u)
F=$E/Olayinka_Egbedokun_environment.txt; : > "$F"
for s in $PRIMARY $REPLICA; do
  v=$(val $s "SHOW server_version" | awk '{print $1}')
  [ "$v" = "$pinned" ] || fail "$s is '$v', compose.yml pins '$pinned'"
  say "$s: Docker image $(docker inspect -f '{{.Config.Image}}' $s); PostgreSQL $v; in recovery (standby): $(val $s "SELECT pg_is_in_recovery()")"
done

echo "Loading the P1 schema and P2 seed on the primary..."
sql $PRIMARY -q < portfolio-1-database-design/Olayinka_Egbedokun_schema.sql > /dev/null
sql $PRIMARY -q < portfolio-2-query-optimisation/Olayinka_Egbedokun_seed.sql > /dev/null
# A fingerprint of the whole database: every row of every table, as JSON, minus
# the timestamp columns (set by now(), so they differ between runs), hashed.
ROWS=$(val $PRIMARY "SELECT string_agg(format('SELECT %L || (to_jsonb(x) - %L::text[])::text AS t FROM %I x', table_name,
         (SELECT coalesce(array_agg(column_name::text), '{}') FROM information_schema.columns c
          WHERE c.table_schema = 'public' AND c.table_name = t.table_name AND c.data_type LIKE 'timestamp%'), table_name), ' UNION ALL ')
       FROM information_schema.tables t WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")
SUM="SELECT (SELECT count(*) FROM result_amendments) || ' corrections; ' || count(*) || ' rows in all tables; md5 '
            || md5(string_agg(t, '|' ORDER BY t)) FROM ($ROWS) all_rows"

# ---------------------------------------------------------------------------
echo "Scenario 1: replication..."
F=$E/Olayinka_Egbedokun_s1_replication.txt; : > "$F"
caught_up
say "=== Replication status, read on the primary"
sql $PRIMARY -c "$STATUS" >> "$F"
[ "$(val $PRIMARY "SELECT application_name || ' ' || state || ' ' || sync_state FROM pg_stat_replication")" = "replica1 streaming async" ] \
  || fail "scenario 1: expected one asynchronous replica, replica1, streaming"
say "=== The replica was cloned before any data existed; the schema and seed loaded afterwards on the primary reached it"
p=$(val $PRIMARY "$SUM"); r=$(val $REPLICA "$SUM")
say "primary: $p"; say "replica: $r"
[ "$p" = "$r" ] || fail "scenario 1: the replica's data differs from the primary's"
say
before=$(val $REPLICA "$CGPA")
say "Zainab's CGPA on the replica: $before"
say "=== On the primary"
correct $PRIMARY 74.00 >> "$F"
caught_up
say "=== On the replica, polled every 0.1 s until the correction was applied"
say "Zainab's CGPA on the replica: $(val $REPLICA "$CGPA") (primary: $(val $PRIMARY "$CGPA"))"
lag=$(val $REPLICA "SELECT round(extract(epoch FROM now() - pg_last_xact_replay_timestamp()) * 1000)")
say "time since the applied correction committed on the primary: $lag ms (an upper bound on the replication delay)"
[ "$lag" -lt 1000 ] || fail "scenario 1: the correction should reach the replica within a second"
[ "$(val $REPLICA "$CGPA")" = "$(val $PRIMARY "$CGPA")" ] || fail "scenario 1: the replica does not show the correction"
[ "$(val $REPLICA "$CGPA")" != "$before" ] || fail "scenario 1: the correction should change the CGPA"
say
say "=== The same correction sent to the replica"
correct $REPLICA 80.00 >> "$F" 2>&1 || true
grep -q 'ERROR: *cannot execute INSERT in a read-only transaction' "$F" || fail "scenario 1: the replica should refuse writes"

# ---------------------------------------------------------------------------
echo "Scenario 2: eventual consistency..."
F=$E/Olayinka_Egbedokun_s2_eventual.txt; : > "$F"
val $REPLICA "SELECT pg_wal_replay_pause()" > /dev/null
until_true $REPLICA "SELECT pg_get_wal_replay_pause_state() = 'paused'" "scenario 2: replay did not pause"
say "=== The replica's replay is paused (it still receives WAL, but does not apply it)"
before=$(val $REPLICA "$CGPA")
say "Zainab's CGPA on the replica: $before"
say "=== On the primary"
correct $PRIMARY 52.00 >> "$F"
lsn=$(val $PRIMARY "SELECT pg_current_wal_lsn()")
until_true $PRIMARY "SELECT flush_lsn >= '$lsn' FROM pg_stat_replication" "scenario 2: the replica did not receive the WAL"
say "=== Replication status, read on the primary: the correction has reached the replica's disk, not its data"
sql $PRIMARY -c "SELECT application_name, flush_lsn AS received_up_to, replay_lsn AS applied_up_to,
                        pg_wal_lsn_diff(flush_lsn, replay_lsn) AS bytes_not_applied FROM pg_stat_replication" >> "$F"
[ "$(val $PRIMARY "SELECT flush_lsn > replay_lsn FROM pg_stat_replication")" = t ] || fail "scenario 2: received WAL should be waiting to be applied"
p=$(val $PRIMARY "$CGPA"); r=$(val $REPLICA "$CGPA")
say "Zainab's CGPA on the primary: $p"
say "Zainab's CGPA on the replica: $r (stale)"
[ "$p" != "$before" ] || fail "scenario 2: the correction should change the CGPA"
[ "$r" = "$before" ] || fail "scenario 2: the paused replica should still show the old CGPA"
say "=== Replay resumed"
val $REPLICA "SELECT pg_wal_replay_resume()" > /dev/null
caught_up
r=$(val $REPLICA "$CGPA")
say "Zainab's CGPA on the replica: $r (caught up)"
[ "$r" = "$p" ] || fail "scenario 2: the replica should catch up"

# ---------------------------------------------------------------------------
echo "Scenario 3: synchronous replication..."
F=$E/Olayinka_Egbedokun_s3_synchronous.txt; : > "$F"
val $PRIMARY "ALTER SYSTEM SET synchronous_standby_names = 'replica1'" > /dev/null
val $PRIMARY "SELECT pg_reload_conf()" > /dev/null
until_true $PRIMARY "SELECT sync_state = 'sync' FROM pg_stat_replication" "scenario 3: the replica did not become synchronous"
say "=== synchronous_standby_names = 'replica1'; replication status, read on the primary"
sql $PRIMARY -c "$STATUS" >> "$F"
val $REPLICA "SELECT pg_wal_replay_pause()" > /dev/null
until_true $REPLICA "SELECT pg_get_wal_replay_pause_state() = 'paused'" "scenario 3: replay did not pause"
before=$(val $PRIMARY "$CGPA")
say "=== The replica's replay is paused. Zainab's CGPA: $before"
say "=== The head commits a correction with synchronous_commit = remote_apply (in the background)"
correct $PRIMARY 66.00 remote_apply > "$E/s3.tmp" 2>&1 &
writer=$!
sleep 2
say "=== Two seconds later, on the primary: the head's session is still waiting"
sql $PRIMARY -c "SELECT application_name, wait_event_type, wait_event, left(query, 30) AS query
                 FROM pg_stat_activity WHERE application_name = 'p5_writer'" >> "$F"
[ "$(val $PRIMARY "SELECT wait_event FROM pg_stat_activity WHERE application_name = 'p5_writer'")" = SyncRep ] \
  || fail "scenario 3: the commit should be waiting for the replica (SyncRep)"
o=$(val $PRIMARY "$CGPA"); r=$(val $REPLICA "$CGPA")
say "Zainab's CGPA read by another session on the primary: $o"
say "Zainab's CGPA on the replica: $r"
[ "$o" = "$before" ] || fail "scenario 3: a commit still waiting for the replica should not be visible yet"
[ "$r" = "$before" ] || fail "scenario 3: the paused replica should show the old CGPA"
sleep 1
say "=== Three seconds after the commit was sent, replay resumed"
val $REPLICA "SELECT pg_wal_replay_resume()" > /dev/null
wait $writer || fail "scenario 3: the correction failed"
cat "$E/s3.tmp" >> "$F"; rm -f "$E/s3.tmp"
p=$(val $PRIMARY "$CGPA"); r=$(val $REPLICA "$CGPA")
say "Zainab's CGPA on the primary: $p"
say "Zainab's CGPA on the replica, read straight after the commit returned (no waiting): $r"
waited=$(sed -n 's/.*remote_apply); the commit returned after \([0-9.]*\) s$/\1/p' "$F" | head -1)
awk -v w="$waited" 'BEGIN { exit !(w >= 2.5) }' || fail "scenario 3: the commit should have waited about 3 s (it took '$waited' s)"
[ "$p" != "$before" ] || fail "scenario 3: the correction should change the CGPA"
[ "$r" = "$p" ] || fail "scenario 3: after a remote_apply commit returns, the replica must show it"
say
say "=== Scenario 3b: the synchronous replica goes offline (as in a network partition)"
docker stop $REPLICA > /dev/null
before=$(val $PRIMARY "$CGPA")
correct $PRIMARY 58.00 remote_apply > "$E/s3.tmp" 2>&1 &
writer=$!
sleep 2
say "=== Two seconds later, on the primary: the commit is waiting for a replica that is not there"
sql $PRIMARY -c "SELECT application_name, wait_event_type, wait_event, left(query, 30) AS query
                 FROM pg_stat_activity WHERE application_name = 'p5_writer'" >> "$F"
[ "$(val $PRIMARY "SELECT wait_event FROM pg_stat_activity WHERE application_name = 'p5_writer'")" = SyncRep ] \
  || fail "scenario 3b: the commit should wait while the synchronous replica is offline"
o=$(val $PRIMARY "$CGPA")
say "Zainab's CGPA read by another session on the primary: $o"
[ "$o" = "$before" ] || fail "scenario 3b: the waiting commit should not be visible"
say "=== The replica comes back"
docker start $REPLICA > /dev/null
wait $writer || fail "scenario 3b: the correction failed"
cat "$E/s3.tmp" >> "$F"; rm -f "$E/s3.tmp"
p=$(val $PRIMARY "$CGPA"); r=$(val $REPLICA "$CGPA")
say "Zainab's CGPA on the primary: $p; on the replica: $r"
[ "$p" != "$before" ] || fail "scenario 3b: the correction should change the CGPA"
[ "$r" = "$p" ] || fail "scenario 3b: after a remote_apply commit returns, the replica must show it"
val $PRIMARY "ALTER SYSTEM RESET synchronous_standby_names" > /dev/null
val $PRIMARY "SELECT pg_reload_conf()" > /dev/null
until_true $PRIMARY "SELECT sync_state = 'async' FROM pg_stat_replication" "scenario 3: the replica did not return to asynchronous"
say "=== synchronous_standby_names reset; the replica is asynchronous again"

# ---------------------------------------------------------------------------
echo "Scenario 4: failover..."
F=$E/Olayinka_Egbedokun_s4_failover.txt; : > "$F"
caught_up
c0=$(val $PRIMARY "$SUM")
say "=== Data on the primary: $c0"
say "=== The replica goes offline"
docker stop $REPLICA > /dev/null
say "=== On the primary, with the replica offline (asynchronous replication, so the commit does not wait)"
correct $PRIMARY 45.00 >> "$F"
c1=$(val $PRIMARY "$SUM")
say "Data on the primary: $c1"
[ "$c1" != "$c0" ] || fail "scenario 4: the correction should change the data"
say "=== The primary crashes (killed)"
docker kill $PRIMARY > /dev/null
say "=== The replica comes back; the primary is unreachable"
docker start $REPLICA > /dev/null
until_true $REPLICA "SELECT pg_is_in_recovery()" "scenario 4: the replica did not restart as a standby"
say "replica in recovery (standby): $(val $REPLICA "SELECT pg_is_in_recovery()")"
say "=== Promote the replica"
[ "$(val $REPLICA "SELECT pg_promote()")" = t ] || fail "scenario 4: promotion failed"
say "pg_promote() returned true; in recovery: $(val $REPLICA "SELECT pg_is_in_recovery()")"
[ "$(val $REPLICA "SELECT pg_is_in_recovery()")" = f ] || fail "scenario 4: the promoted server is still a standby"
c2=$(val $REPLICA "$SUM")
say "Data on the new primary: $c2"
say "Zainab's CGPA on the new primary: $(val $REPLICA "$CGPA")"
[ "$c2" = "$c0" ] || fail "scenario 4: everything replicated before the replica went offline should survive"
say "(identical to the data before the replica went offline: the correction committed while it was offline is lost)"
say "=== The new primary accepts writes"
before=$(val $REPLICA "$CGPA")
correct $REPLICA 80.00 >> "$F"
say "Zainab's CGPA on the new primary: $(val $REPLICA "$CGPA")"
[ "$(val $REPLICA "$CGPA")" != "$before" ] || fail "scenario 4: the new primary should accept the correction"

async=$(cat $E/Olayinka_Egbedokun_s*.txt | grep 'synchronous_commit = on); the commit returned after')
[ "$(echo "$async" | wc -l | tr -d ' ')" = 4 ] && ! echo "$async" | grep -qv 'after 0.0 s$' \
  || fail "every asynchronous commit should return in 0.0 s"

echo "All checks passed. Evidence in $E/"
echo "(the old primary is left stopped; '$DC down -v' removes both servers and their data)"
