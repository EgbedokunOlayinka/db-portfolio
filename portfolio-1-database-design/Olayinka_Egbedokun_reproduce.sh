#!/usr/bin/env bash
# Wavers University — Portfolio 1: rebuild the schema and regenerate every evidence file
#
#   bash portfolio-1-database-design/Olayinka_Egbedokun_reproduce.sh
#
# (from any directory). It starts the database container if needed, builds
# the schema in a fresh database, and then checks, writing each result to
# evidence/:
#   1. the server is the version pinned in compose.yml;
#   2. the ER diagram matches the schema, column for column;
#   3. every rule test passes;
#   4. the tests can fail: with any one trigger removed, its tests fail;
#   5. two students racing for the last place cannot both get it, at every
#      isolation level;
#   6. every figure and rule mapping stated in the documents matches 1-5.
# It exits non-zero as soon as any check does not hold.

set -euo pipefail
cd "$(dirname "$0")/.."
CONTAINER=wu-postgres
DB=wavers_p1
P1=portfolio-1-database-design
E=$P1/evidence
mkdir -p "$E"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

psql_on() { local db=$1; shift; docker exec -i "$CONTAINER" psql -U wavers -X -v ON_ERROR_STOP=1 -d "$db" "$@"; }
fresh_db() { psql_on wavers -q -c "DROP DATABASE IF EXISTS $1 WITH (FORCE)" -c "CREATE DATABASE $1"; }
drop_db() { psql_on wavers -q -c "DROP DATABASE IF EXISTS $1 WITH (FORCE)"; }
fail() { echo "CHECK FAILED: $*" >&2; exit 1; }
count_lines() { if [ -z "$1" ]; then echo 0; else echo "$1" | wc -l | tr -d ' '; fi; }

docker compose up -d --wait --quiet-pull > /dev/null 2>&1 || fail "could not start the containers (is Docker running?)"

echo "Building $DB from empty..."
fresh_db "$DB" 2> /dev/null

# 1. The server must be the version compose.yml pins.
pinned=$(sed -n 's/^ *image: postgres:\([0-9.]*\) *$/\1/p' compose.yml)
running=$(psql_on "$DB" -tA -c "SHOW server_version" | awk '{print $1}')
{
  echo "Docker image: $(docker inspect -f '{{.Config.Image}}' "$CONTAINER")"
  echo "Image digest: $(docker image inspect -f '{{index .RepoDigests 0}}' "$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")")"
  echo "Version pinned in compose.yml: $pinned; version running: $running"
  echo
  psql_on "$DB" -c "SELECT version();"
} > $E/Olayinka_Egbedokun_environment.txt
[ -n "$pinned" ] && [ "$running" = "$pinned" ] || fail "server is '$running', compose.yml pins '$pinned'"

psql_on "$DB" < $P1/Olayinka_Egbedokun_schema.sql > $E/Olayinka_Egbedokun_schema_run.txt
grep -q '^COMMIT$' $E/Olayinka_Egbedokun_schema_run.txt || fail "schema did not commit"
psql_on "$DB" -c '\dt' -c '\dv' -c '\df' > $E/Olayinka_Egbedokun_objects.txt
psql_on "$DB" -c '\d faculties' -c '\d departments' -c '\d programmes' -c '\d lecturers' \
  -c '\d academic_sessions' -c '\d semesters' -c '\d students' -c '\d courses' \
  -c '\d course_prerequisites' -c '\d course_offerings' -c '\d registrations' \
  -c '\d grade_scale' -c '\d results' -c '\d result_amendments' \
  > $E/Olayinka_Egbedokun_table_definitions.txt
psql_on "$DB" -c '\dp' > $E/Olayinka_Egbedokun_privileges.txt

# 2. The ER diagram: the same columns in every table, and one relationship
#    line per foreign key (compared as table pairs).
echo "Checking the ER diagram against the database..."
MMD=$P1/Olayinka_Egbedokun_er_diagram.mmd
diagram_columns=$(awk '/^ *[A-Z_]+ \{/ {t=tolower($1)} /^ *\}/ {t=""} t && NF >= 2 && !/\{/ {print t "." $2}' $MMD | sort)
db_columns=$(psql_on "$DB" -tA -c "SELECT c.table_name || '.' || c.column_name FROM information_schema.columns c
                                    JOIN information_schema.tables t USING (table_schema, table_name)
                                    WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'" | sort)
diagram_links=$(grep -E '^ *[A-Z_]+ [|}o]{2}--[|{o]{2} [A-Z_]+ :' $MMD | awk '{a=tolower($1); b=tolower($3); print (a<b ? a" "b : b" "a)}' | sort)
db_links=$(psql_on "$DB" -tA -F ' ' -c "SELECT least(conrelid::regclass::text, confrelid::regclass::text), greatest(conrelid::regclass::text, confrelid::regclass::text)
                                         FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace" | sort)
n_cols=$(count_lines "$db_columns"); n_fks=$(count_lines "$db_links")
{
  echo "Columns: diagram $(count_lines "$diagram_columns"), database $n_cols"
  echo "Relationships: diagram $(count_lines "$diagram_links"), foreign keys $n_fks"
  echo
  echo "Differences in columns (< diagram only, > database only):"
  diff <(echo "$diagram_columns") <(echo "$db_columns") || true
  echo "Differences in relationships (< diagram only, > database only):"
  diff <(echo "$diagram_links") <(echo "$db_links") || true
} > $E/Olayinka_Egbedokun_er_diagram_check.txt
[ "$diagram_columns" = "$db_columns" ] || fail "ER diagram columns differ from the schema (see er_diagram_check)"
[ "$diagram_links" = "$db_links" ] || fail "ER diagram relationships differ from the foreign keys (see er_diagram_check)"
echo "  diagram matches: $n_cols columns, $n_fks relationships"

# 3. The rule tests. The number expected is counted from the test file.
echo "Running the rule tests..."
psql_on "$DB" < $P1/Olayinka_Egbedokun_constraint_tests.sql > $E/Olayinka_Egbedokun_constraint_tests.txt 2> "$TMP/err" \
  || { grep -v NOTICE "$TMP/err" >&2; fail "the test scenario stopped with an error"; }
expected=$(grep -oE "expect_(error|true)[(]'([TP][0-9]+|H0)'" $P1/Olayinka_Egbedokun_constraint_tests.sql | wc -l | tr -d ' ')
result=$(grep -E '^RESULT: ' $E/Olayinka_Egbedokun_constraint_tests.txt || true)
[ "$result" = "RESULT: $expected PASS, 0 FAIL" ] || fail "tests: got '$result', expected 'RESULT: $expected PASS, 0 FAIL'"
echo "  $result"

# 4. Mutation check: build the schema again with one trigger removed and
#    rerun every test, once per trigger. Each removal must make at least one
#    test fail; for the registration trigger, exactly the tests of the rules
#    it enforces must fail.
echo "Mutation check (each trigger removed in turn)..."
triggers=$(psql_on "$DB" -tA -F ' ' -c "SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE NOT tgisinternal ORDER BY tgname")
n_triggers=$(count_lines "$triggers")
{
  echo "For each trigger: the schema is rebuilt without it, every test is rerun,"
  echo "and the tests that now fail are listed. Every trigger must be caught."
  echo
  while read -r trg tbl <&3; do
    fresh_db "${DB}_mutant" 2> /dev/null
    psql_on "${DB}_mutant" -q < $P1/Olayinka_Egbedokun_schema.sql > /dev/null
    psql_on "${DB}_mutant" -q -c "DROP TRIGGER $trg ON $tbl" < /dev/null
    psql_on "${DB}_mutant" < $P1/Olayinka_Egbedokun_constraint_tests.sql > "$TMP/mutant.txt" 2>&1 || true
    if grep -q '^RESULT: ' "$TMP/mutant.txt"; then
      fails=$(grep -E '^ [TP][0-9]+ +[|] R[0-9]+ +[|] FAIL' "$TMP/mutant.txt" | awk '{print $1}' | tr '\n' ' ' || true)
      echo "$trg ($tbl): $(echo $fails | wc -w | tr -d ' ') failing: $fails"
    else
      # A valid step of the test scenario itself broke: also a detection.
      echo "$trg ($tbl): scenario stopped: $(grep -m1 '^psql.*ERROR\|^ERROR' "$TMP/mutant.txt" | sed 's/^psql:[^E]*//')"
    fi
  done 3<<< "$triggers"
} > $E/Olayinka_Egbedokun_mutation_check.txt
drop_db "${DB}_mutant"
uncaught=$(grep -E ': 0 failing' $E/Olayinka_Egbedokun_mutation_check.txt || true)
[ -z "$uncaught" ] || fail "mutation check: no test fails without: $uncaught"
reg_fails=$(sed -n 's/^trg_registration_insert_guard (registrations): [0-9]* failing: //p' $E/Olayinka_Egbedokun_mutation_check.txt)
[ "$reg_fails" = "T32 T33 T34 T35 T36 T37 T39 T81 " ] || fail "mutation check: registration guard removal failed '$reg_fails'"
n_reg_fails=$(echo $reg_fails | wc -w | tr -d ' ')
echo "  all $n_triggers triggers caught by at least one test"

# 5. Concurrency: two students race for the last place on a course, once
#    per isolation level, both connected as portal_app. Session A starts its
#    transaction and reads, then waits while B registers and commits, then
#    tries to register. Exactly one of them must get the place.
echo "Concurrency check (last place, three isolation levels)..."
CDB=${DB}_concurrency
fresh_db "$CDB" 2> /dev/null
psql_on "$CDB" -q < $P1/Olayinka_Egbedokun_schema.sql > /dev/null
psql_on "$CDB" -q < $P1/Olayinka_Egbedokun_concurrency_fixture.sql > /dev/null
register() {   # register <matric> <course code>
  echo "INSERT INTO registrations (student_id, offering_id)
        SELECT (SELECT student_id FROM students WHERE matric_no = '$1'),
               (SELECT o.offering_id FROM course_offerings o JOIN courses c USING (course_id) WHERE c.code = '$2');"
}
{
  echo "Each course has capacity 1. Session A begins at the isolation level shown"
  echo "and reads; session B then registers and commits; A then registers."
  echo
  for pair in "READ COMMITTED:CSC301" "REPEATABLE READ:CSC303" "SERIALIZABLE:CSC305"; do
    level=${pair%%:*}; code=${pair##*:}
    { echo "SET ROLE portal_app; BEGIN ISOLATION LEVEL $level;"
      echo "SELECT count(*) AS places_taken_as_seen_by_A FROM registrations g JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id) WHERE c.code = '$code';"
      echo "SELECT pg_sleep(2);"
      register WU/2025/0001 "$code"
      echo "COMMIT;"; } | psql_on "$CDB" > "$TMP/a.txt" 2>&1 &
    a_pid=$!
    sleep 1
    { echo "SET ROLE portal_app;"; register WU/2025/0002 "$code"; } | psql_on "$CDB" > "$TMP/b.txt" 2>&1 || true
    wait $a_pid || true
    taken=$(psql_on "$CDB" -tA -c "SELECT count(*) FROM registrations g JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id) WHERE c.code = '$code' AND g.status = 'registered'")
    echo "== $level, $code"
    echo "Session B: $(grep -E '^(INSERT|ERROR)' $TMP/b.txt | head -1)"
    echo "Session A: $(grep -E '^(INSERT|ERROR)' $TMP/a.txt | head -1)"
    echo "Places taken: $taken of 1"
    echo
  done
} > $E/Olayinka_Egbedokun_concurrency_check.txt
drop_db "$CDB"
[ "$(grep -c '^Places taken: 1 of 1$' $E/Olayinka_Egbedokun_concurrency_check.txt)" = 3 ] || fail "concurrency: a course was overfilled (see concurrency_check)"
[ "$(grep -c '^Session B: INSERT 0 1$' $E/Olayinka_Egbedokun_concurrency_check.txt)" = 3 ] || fail "concurrency: session B should always succeed"
grep -A2 '^== READ COMMITTED' $E/Olayinka_Egbedokun_concurrency_check.txt | grep -q 'Session A: ERROR: .*is full' || fail "concurrency: READ COMMITTED should reject A as full"
[ "$(grep -c 'Session A: ERROR: *could not serialize access' $E/Olayinka_Egbedokun_concurrency_check.txt)" = 2 ] || fail "concurrency: REPEATABLE READ and SERIALIZABLE should fail A with a serialization error"
echo "  one place, one registration, at all three levels"

# 6. Every figure and mapping the documents state is checked against what
#    was just measured: the expected text is built from the measured values.
echo "Checking the documents against the evidence..."
n_tables=$(psql_on "$DB" -tA -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")
n_views=$(psql_on "$DB" -tA -c "SELECT count(*) FROM information_schema.views WHERE table_schema = 'public'")
log_map=$(grep -oE '^ [TP][0-9]+ +[|] R[0-9]+ ' $E/Olayinka_Egbedokun_constraint_tests.txt | awk '{print $1, $3}' | sort)
n_rules=$(echo "$log_map" | awk '{print $2}' | sort -u | wc -l | tr -d ' ')
DESIGN=$P1/Olayinka_Egbedokun_database_design.md
# The rule table's last column lists tests as "T01–T07, P11": expand ranges.
doc_map=$(awk -F'|' '/^[|] R[0-9]+ [|]/ {r=$2; gsub(/ /,"",r); n=split($5, parts, ","); for (i=1;i<=n;i++) { p=parts[i]; gsub(/ /,"",p)
             if (split(p, ab, "–") == 2) { pre=substr(ab[1],1,1); for (k=substr(ab[1],2)+0; k<=substr(ab[2],2)+0; k++) printf "%s%02d %s\n", pre, k, r }
             else print p, r } }' $DESIGN | sort)
# Every constraint or trigger the rule table names must be expected by a test.
named=$(awk -F'|' '/^[|] R[0-9]+ [|]/ {print $4}' $DESIGN | grep -oE '`(chk|uq|fk|ex|trg)_[a-z_]+`' | tr -d '`' | sort -u)
untested=$(for n in $named; do grep -q "'$n'" $P1/Olayinka_Egbedokun_constraint_tests.sql || echo "$n"; done)
{
  claim() { if grep -qF -- "$2" "$1"; then echo "OK    $1: \"$2\""; else echo "WRONG $1: expected \"$2\""; fi; }
  claim $P1/README.md "$n_tables tables, $n_views views"
  claim $DESIGN "has $n_tables tables and $n_views views"
  claim $P1/Olayinka_Egbedokun_normalisation.md "these are the schema's $n_tables tables"
  claim $P1/README.md "$n_cols of $n_cols columns and $n_fks of $n_fks foreign keys"
  claim $P1/README.md "${result#RESULT: }"
  claim $P1/README.md "all $n_triggers triggers"
  claim $P1/README.md "exactly its $n_reg_fails tests fail"
  claim $P1/README.md "Each of the $n_rules business rules (R1–R$n_rules"
  if [ "$(sed -n '/^```mermaid$/,/^```$/p' $P1/Olayinka_Egbedokun_er_diagram.md | sed '1d;$d')" = "$(cat $MMD)" ]; then
    echo "OK    the diagram shown in Olayinka_Egbedokun_er_diagram.md is identical to Olayinka_Egbedokun_er_diagram.mmd"
  else echo "WRONG the diagram in Olayinka_Egbedokun_er_diagram.md differs from Olayinka_Egbedokun_er_diagram.mmd"; fi
  if [ "$doc_map" = "$log_map" ]; then echo "OK    the design document's rule-to-test table matches the test log ($(count_lines "$log_map") tests)"
  else echo "WRONG the rule-to-test table differs from the test log (< document, > test log):"; diff <(echo "$doc_map") <(echo "$log_map") || true; fi
  if [ -z "$untested" ]; then echo "OK    every one of the $(count_lines "$named") constraints and trigger rules named in the rule table is expected by a test"
  else echo "WRONG named in the rule table but expected by no test: $(echo $untested)"; fi
} > $E/Olayinka_Egbedokun_doc_claims_check.txt
if grep -q '^WRONG' $E/Olayinka_Egbedokun_doc_claims_check.txt; then cat $E/Olayinka_Egbedokun_doc_claims_check.txt >&2; fail "a document states something the evidence does not"; fi
echo "  $(grep -c '^OK' $E/Olayinka_Egbedokun_doc_claims_check.txt) document checks OK"

echo "Portfolio 1 evidence regenerated in $E/"
