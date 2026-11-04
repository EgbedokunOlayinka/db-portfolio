#!/usr/bin/env bash
# Wavers University — Portfolio 3: run every transaction scenario and regenerate the evidence
#
#   bash portfolio-3-transactions-concurrency/Olayinka_Egbedokun_reproduce.sh
#
# Builds a fresh database (P1 schema, P2 seed, P3 fixture), runs scenarios
# 1-4, writes each log to evidence/ and checks every outcome; any outcome
# that differs from the expected one stops the run. Concurrent sessions are
# separate psql connections started a second apart; the waits inside the
# scenarios (2 s) leave a wide margin, so the order of events is fixed.

set -euo pipefail
cd "$(dirname "$0")/.."
CONTAINER=wu-postgres
DB=wavers_p3
P3=portfolio-3-transactions-concurrency
E=$P3/evidence
mkdir -p "$E"

psql_db() { docker exec -i "$CONTAINER" psql -U wavers -X -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
value() { psql_db -tA -c "$1"; }
fail() { echo "CHECK FAILED: $*" >&2; exit 1; }
regs() {   # regs <matric>: the student's registrations in 2024/2025 first semester
  value "SELECT count(*) FROM registrations g JOIN students s USING (student_id) JOIN course_offerings o USING (offering_id)
         JOIN semesters m USING (semester_id) JOIN academic_sessions a USING (session_id)
         WHERE s.matric_no = '$1' AND a.name = '2024/2025' AND m.term = 'first' AND g.status = 'registered'"
}
cgpa() { value "SELECT cgpa FROM student_cgpa WHERE student_id = (SELECT student_id FROM students WHERE matric_no = 'WU/2023/0003')"; }
score() { value "SELECT r.score FROM results r JOIN registrations g USING (registration_id) JOIN students s USING (student_id)
                 JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id)
                 WHERE s.matric_no = '$1' AND c.code = 'CSC311'"; }

docker compose up -d --wait --quiet-pull > /dev/null 2>&1 || fail "could not start the containers (is Docker running?)"
pinned=$(sed -n 's/^ *image: postgres:\([0-9.]*\) *$/\1/p' compose.yml)
running=$(docker exec -i "$CONTAINER" psql -U wavers -X -d wavers -tAc "SHOW server_version" | awk '{print $1}')
[ "$running" = "$pinned" ] || fail "server is '$running', compose.yml pins '$pinned'"
echo "Docker image: $(docker inspect -f '{{.Config.Image}}' "$CONTAINER"); PostgreSQL $running" > $E/Olayinka_Egbedokun_environment.txt

echo "Building $DB (P1 schema, P2 seed, P3 fixture)..."
docker exec -i "$CONTAINER" psql -U wavers -X -q -d wavers -c "DROP DATABASE IF EXISTS $DB WITH (FORCE)" -c "CREATE DATABASE $DB" 2> /dev/null
psql_db -q < portfolio-1-database-design/Olayinka_Egbedokun_schema.sql > /dev/null
psql_db -q < portfolio-2-query-optimisation/Olayinka_Egbedokun_seed.sql > /dev/null
psql_db -q < $P3/Olayinka_Egbedokun_fixture.sql > /dev/null

# ---------------------------------------------------------------------------
echo "Scenario 1: commit..."
{ echo "=== Session A"
  psql_db -e < $P3/Olayinka_Egbedokun_s1_commit.sql
  echo
  echo "=== Session B, a separate connection, after A committed"
  echo "Amaka's registrations in 2024/2025 first semester: $(regs WU/2023/0001)"
} > $E/Olayinka_Egbedokun_s1_commit.txt 2>&1
[ "$(regs WU/2023/0001)" = 3 ] || fail "scenario 1: Amaka should have 3 registrations"

# ---------------------------------------------------------------------------
echo "Scenario 2: rollback..."
# stdout and stderr are merged inside the container, so errors appear in order.
docker exec -i "$CONTAINER" sh -c "psql -U wavers -X -d $DB -e 2>&1" < $P3/Olayinka_Egbedokun_s2_rollback.sql > $E/Olayinka_Egbedokun_s2_rollback.txt || true
{ echo
  echo "=== Afterwards, from a separate connection: registrations in 2024/2025 first semester"
  echo "2a Yusuf (rolled back):              $(regs WU/2023/0006)"
  echo "2b Kelechi (failed on the 5th):      $(regs WU/2023/0004)"
  echo "2c Ngozi (savepoint before the 5th): $(regs WU/2023/0005)"
} >> $E/Olayinka_Egbedokun_s2_rollback.txt
[ "$(regs WU/2023/0006)" = 0 ] || fail "scenario 2a: the rolled-back registrations persisted"
[ "$(regs WU/2023/0004)" = 0 ] || fail "scenario 2b: the failed transaction left registrations behind"
[ "$(regs WU/2023/0005)" = 4 ] || fail "scenario 2c: the savepoint should keep exactly 4 registrations"
grep -qE '(^|: )ERROR: +unit limit' $E/Olayinka_Egbedokun_s2_rollback.txt || fail "scenario 2b: the 5th registration should break the unit limit"
# the registrations really were made before being undone: 2a's two, and
# the four that 2b and 2c each made before the fifth
[ "$(grep -c '^INSERT 0 2$' $E/Olayinka_Egbedokun_s2_rollback.txt)" = 1 ] || fail "scenario 2a: expected one INSERT of 2 rows"
[ "$(grep -c '^INSERT 0 1$' $E/Olayinka_Egbedokun_s2_rollback.txt)" = 8 ] || fail "scenarios 2b/2c: expected 8 single-row INSERTs"
grep -q 'current transaction is aborted' $E/Olayinka_Egbedokun_s2_rollback.txt || fail "scenario 2b: the transaction should be aborted after the failure"

# ---------------------------------------------------------------------------
# Scenario 3: A reads Zainab's CGPA twice; B commits a correction in between.
isolation() {   # isolation <level> <new score>
  before=$(cgpa)
  psql_db -v level="$1" < $P3/Olayinka_Egbedokun_s3_registry.sql > "$E/s3.tmp.a" 2>&1 &
  a=$!
  sleep 1
  psql_db -v score="$2" < $P3/Olayinka_Egbedokun_s3_correction.sql > "$E/s3.tmp.b" 2>&1
  wait $a
  after=$(cgpa)
  echo "=== $1 (Zainab's CGPA before: $before)"
  grep -v '^$' "$E/s3.tmp.a" | sed -n 1p     # in time order: A's first read,
  grep -v '^$' "$E/s3.tmp.b"                 # B's commit,
  grep -v '^$' "$E/s3.tmp.a" | sed -n 2p     # A's second read
  echo "Fresh read after both committed: CGPA = $after"
  echo
  rm -f "$E"/s3.tmp.*
}
echo "Scenario 3: isolation levels..."
{ echo "Session A reads at t=0 s and t=2 s inside one transaction; session B commits a correction at t=1 s."
  echo
  isolation "READ COMMITTED" 45.00
  isolation "REPEATABLE READ" 50.00
} > $E/Olayinka_Egbedokun_s3_isolation.txt
reads() { sed -n "/^=== $1/,/^Fresh/p" $E/Olayinka_Egbedokun_s3_isolation.txt | sed -n 's/^A: .*CGPA = //p' | tr '\n' ' '; }
# Each first read must come before the correction (it equals the CGPA before),
# so a pass cannot come from a session that started late.
field() { sed -n "/^=== $1/,/^Fresh/p" $E/Olayinka_Egbedokun_s3_isolation.txt | sed -n "s/^$2//p" | tr -d ')'; }
read -r rc1 rc2 <<< "$(reads 'READ COMMITTED')"; rc_before=$(field 'READ COMMITTED' ".*CGPA before: "); rc_after=$(field 'READ COMMITTED' 'Fresh read after both committed: CGPA = ')
read -r rr1 rr2 <<< "$(reads 'REPEATABLE READ')"; rr_before=$(field 'REPEATABLE READ' ".*CGPA before: "); rr_after=$(field 'REPEATABLE READ' 'Fresh read after both committed: CGPA = ')
[ "$rc1" = "$rc_before" ] && [ "$rc2" = "$rc_after" ] && [ "$rc1" != "$rc2" ] || fail "scenario 3, READ COMMITTED: expected $rc_before then $rc_after, got $rc1, $rc2"
[ "$rr1" = "$rr_before" ] && [ "$rr2" = "$rr_before" ] && [ "$rr_after" != "$rr_before" ] || fail "scenario 3, REPEATABLE READ: expected $rr_before twice, then a new value after; got $rr1, $rr2, $rr_after"

# ---------------------------------------------------------------------------
# Scenario 4: the lecturer (+5) and the head (+3) adjust the same draft score.
adjust() {   # adjust <who> <matric> <add> <pause> <level> <lock>
  psql_db -v who="$1" -v matric="$2" -v add="$3" -v pause="$4" -v level="$5" -v lock="$6" < $P3/Olayinka_Egbedokun_s4_adjust.sql
}
race() {   # race <title> <matric> <level> <lock> <retry: yes/no>
  start=$(score "$2")
  { if adjust lecturer "$2" 5 2 "$3" "$4" > "$E/s4.tmp.a" 2>&1; then :
    elif [ "$5" = yes ] && grep -q 'could not serialize' "$E/s4.tmp.a"; then
      echo "lecturer: transaction failed with a serialization error; retrying" >> "$E/s4.tmp.a"
      adjust lecturer "$2" 5 0 "$3" "$4" >> "$E/s4.tmp.a" 2>&1
    fi; } &
  a=$!
  sleep 1
  adjust head "$2" 3 0 "$3" "$4" > "$E/s4.tmp.b" 2>&1
  wait $a || true
  echo "=== $1 ($2, draft score at start: $start)"
  echo "-- t=0 s, lecturer (adds 5, waits 2 s between read and write):"; grep -v '^$' "$E/s4.tmp.a" | sed 's/^/   /' 
  echo "-- t=1 s, head (adds 3):"; grep -v '^$' "$E/s4.tmp.b" | sed 's/^/   /' 
  echo "Final score: $(score "$2") (both changes applied would give $(awk -v s="$start" 'BEGIN {printf "%.2f", s + 8}'))"
  echo
  rm -f "$E"/s4.tmp.*
}
echo "Scenario 4: lost update and three ways to prevent it..."
{ echo "Lines are grouped by session; the waits shown, and the start times below, give the order of events."
  echo
  race "4a. READ COMMITTED, plain read then write" WU/2023/0002 "READ COMMITTED" "" no
  race "4b. READ COMMITTED, row locked when read (SELECT ... FOR UPDATE)" WU/2023/0004 "READ COMMITTED" "FOR UPDATE" no
  race "4c. REPEATABLE READ, plain read then write, retried on serialization error" WU/2023/0006 "REPEATABLE READ" "" yes
  start=$(score WU/2023/0003)
  psql_db -v who=lecturer -v matric=WU/2023/0003 -v add=5 -v pause=2 < $P3/Olayinka_Egbedokun_s4_atomic.sql > "$E/s4.tmp.a" 2>&1 &
  a=$!; sleep 1
  psql_db -v who=head -v matric=WU/2023/0003 -v add=3 -v pause=0 < $P3/Olayinka_Egbedokun_s4_atomic.sql > "$E/s4.tmp.b" 2>&1
  wait $a
  echo "=== 4d. READ COMMITTED, the database does the arithmetic: UPDATE ... SET score = score + n (WU/2023/0003, draft score at start: $start)"
  echo "-- t=0 s, lecturer (adds 5, keeps the transaction open 2 s):"; grep -v '^$' "$E/s4.tmp.a" | sed 's/^/   /'
  echo "-- t=1 s, head (adds 3):"; grep -v '^$' "$E/s4.tmp.b" | sed 's/^/   /'
  echo "Final score: $(score WU/2023/0003) (both changes applied would give 58.00)"
  rm -f "$E"/s4.tmp.*
} > $E/Olayinka_Egbedokun_s4_lost_update.txt
s4() { score "$1"; }
[ "$(s4 WU/2023/0002)" = 55.00 ] || fail "scenario 4a: expected the lost update to leave 55.00, got $(s4 WU/2023/0002)"
[ "$(s4 WU/2023/0004)" = 58.00 ] || fail "scenario 4b: FOR UPDATE should give 58.00, got $(s4 WU/2023/0004)"
[ "$(s4 WU/2023/0006)" = 58.00 ] || fail "scenario 4c: REPEATABLE READ with retry should give 58.00, got $(s4 WU/2023/0006)"
[ "$(s4 WU/2023/0003)" = 58.00 ] || fail "scenario 4d: the single-statement update should give 58.00, got $(s4 WU/2023/0003)"
section() { sed -n "/^=== $1/,/^Final/p" $E/Olayinka_Egbedokun_s4_lost_update.txt; }
section 4a | grep -q 'lecturer: read score 50.00' && section 4a | grep -q 'head: read score 50.00' \
  || fail "scenario 4a: both should have read 50.00 (the lost update)"
waited=$(section 4b | sed -n 's/.*head: read score 55.00 after waiting \([0-9.]*\) s.*/\1/p')
[ -n "$waited" ] && awk -v w="$waited" 'BEGIN {exit !(w >= 0.5)}' || fail "scenario 4b: the head should wait for the lock, then read 55.00 (waited: '$waited')"
section 4c | grep -q 'could not serialize access' || fail "scenario 4c: the lecturer's first attempt should fail with a serialization error"
section 4c | grep -q 'lecturer: read score 53.00' || fail "scenario 4c: the retry should read the head's 53.00"
waited=$(section 4d | sed -n 's/.*head: score is now 58.00 after waiting \([0-9.]*\) s.*/\1/p')
[ -n "$waited" ] && awk -v w="$waited" 'BEGIN {exit !(w >= 0.5)}' || fail "scenario 4d: the head's UPDATE should wait, then give 58.00 (waited: '$waited')"

echo "All scenarios behaved as expected; evidence in $E/"
