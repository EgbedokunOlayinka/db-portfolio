#!/usr/bin/env bash
# Wavers University — Portfolio 2: rebuild, measure, and regenerate every evidence file
#
#   bash portfolio-2-query-optimisation/Olayinka_Egbedokun_reproduce.sh
#
# Steps (each output goes to evidence/; any failed check stops the run):
#   1. Portfolio 1 schema + hand-checkable seed; the five queries must return
#      exactly the results computed independently (seed_expected.txt).
#   2. Bulk load (4,000 more students, 96,000 more results) through the P1 rules.
#   3. Baseline plans: EXPLAIN (ANALYZE, BUFFERS), 1 warm-up + 5 runs each;
#      then the same with two Portfolio 1 indexes removed (rolled back).
#   4. The precomputed standing: Q4S/Q5S must return the same rows as Q4/Q5;
#      plans without and with its indexes.
#   5. Costs: refresh time with and without those indexes, and staleness.
#   6. Results table for the documents, and a check of every figure the
#      documents state.

set -euo pipefail
cd "$(dirname "$0")/.."
CONTAINER=wu-postgres
DB=wavers_p2
P1=portfolio-1-database-design
P2=portfolio-2-query-optimisation
E=$P2/evidence
mkdir -p "$E"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

psql_db() { docker exec -i "$CONTAINER" psql -U wavers -X -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
fail() { echo "CHECK FAILED: $*" >&2; exit 1; }
# Full-data parameters: an ordinary bulk student, a 1,000-student offering.
BULK=(-v matric=WU/2024/2001 -v course=CSC211 -v session=2025/2026 -v term=first -v programme=CSC-BSC)
PLAN=(-v "EXPLAIN=EXPLAIN (ANALYZE, BUFFERS)")
plans() {   # plans <sql file> <output name>: one warm-up, then five measured runs
  psql_db "${BULK[@]}" "${PLAN[@]}" < "$1" > /dev/null
  for run in 1 2 3 4 5; do echo "##### Run $run of 5"; psql_db "${BULK[@]}" "${PLAN[@]}" < "$1"; done > "$E/Olayinka_Egbedokun_$2.txt"
  awk -f $P2/Olayinka_Egbedokun_plan_summary.awk "$E/Olayinka_Egbedokun_$2.txt" > "$E/Olayinka_Egbedokun_$2_summary.txt"
}
results() { psql_db "${BULK[@]}" -A -t -F '|' < "$1"; }   # query output only

docker compose up -d --wait --quiet-pull > /dev/null 2>&1 || fail "could not start the containers (is Docker running?)"
pinned=$(sed -n 's/^ *image: postgres:\([0-9.]*\) *$/\1/p' compose.yml)
running=$(docker exec -i "$CONTAINER" psql -U wavers -X -d wavers -tAc "SHOW server_version" | awk '{print $1}')
[ -n "$pinned" ] && [ "$running" = "$pinned" ] || fail "server is '$running', compose.yml pins '$pinned'"
{ echo "Docker image: $(docker inspect -f '{{.Config.Image}}' "$CONTAINER")"
  echo "Version pinned in compose.yml: $pinned; version running: $running"; } > $E/Olayinka_Egbedokun_environment.txt

echo "1. Schema and seed; checking the five queries against the expected results..."
docker exec -i "$CONTAINER" psql -U wavers -X -q -d wavers -c "DROP DATABASE IF EXISTS $DB WITH (FORCE)" -c "CREATE DATABASE $DB" 2> /dev/null
psql_db -q < $P1/Olayinka_Egbedokun_schema.sql > /dev/null
psql_db -q < $P2/Olayinka_Egbedokun_seed.sql > /dev/null
psql_db < $P2/Olayinka_Egbedokun_queries.sql > $E/Olayinka_Egbedokun_seed_results.txt
psql_db -A -t -F '|' < $P2/Olayinka_Egbedokun_queries.sql > $TMP/seed_actual.txt
diff $P2/Olayinka_Egbedokun_seed_expected.txt $TMP/seed_actual.txt > /dev/null || fail "seed results differ from the expected results"
echo "   all five queries match the independently computed results"

echo "2. Bulk load (about a minute)..."
psql_db < $P2/Olayinka_Egbedokun_bulk_load.sql > $E/Olayinka_Egbedokun_bulk_load_run.txt
psql_db -c "SELECT (SELECT count(*) FROM students) AS students, (SELECT count(*) FROM courses) AS courses,
                   (SELECT count(*) FROM registrations) AS registrations,
                   (SELECT count(*) FROM results WHERE status = 'approved') AS approved_results,
                   (SELECT count(*) FROM result_amendments) AS corrections" > $E/Olayinka_Egbedokun_volume.txt
read -r n_students n_results <<< "$(psql_db -tA -F ' ' -c "SELECT (SELECT count(*) FROM students), (SELECT count(*) FROM results WHERE status = 'approved')")"
[ "$n_students" = 4006 ] && [ "$n_results" = 96042 ] || fail "volume: $n_students students, $n_results approved results"
results $P2/Olayinka_Egbedokun_queries.sql > $TMP/full_before.txt

echo "3. Baseline plans..."
plans $P2/Olayinka_Egbedokun_queries.sql plans_baseline

cat $P2/Olayinka_Egbedokun_index_experiment.sql $P2/Olayinka_Egbedokun_queries.sql > $TMP/experiment.sql
echo "ROLLBACK;" >> $TMP/experiment.sql
plans $TMP/experiment.sql plans_without_indexes
{ echo "SET jit = off;"; cat $P2/Olayinka_Egbedokun_queries.sql; } > $TMP/jit_off.sql
plans $TMP/jit_off.sql plans_jit_off
for q in Q4 Q5; do   # the analysis says these are faster without JIT; check it
  awk -v q=$q -v f="$E/Olayinka_Egbedokun_plans_jit_off_summary.txt" '$1 == q {b = $5} END {while ((getline l < f) > 0) {split(l, x); if (x[1] == q) j = x[5]}; exit !(j < b)}' \
    $E/Olayinka_Egbedokun_plans_baseline_summary.txt || fail "$q is not faster with JIT off"
done

echo "4. The precomputed standing..."

psql_db < $P2/Olayinka_Egbedokun_summary.sql > /dev/null
results $P2/Olayinka_Egbedokun_queries_summary.sql > $TMP/summary.txt
sed -n '/^=== Q4\./,/^=== Q5\./p' $TMP/full_before.txt | grep -v '^===' > $TMP/q4.txt || true
sed -n '/^=== Q4S/,/^=== Q5S/p' $TMP/summary.txt | grep -v '^===' > $TMP/q4s.txt || true
sed -n '/^=== Q5\./,$p' $TMP/full_before.txt | grep -v '^===' > $TMP/q5.txt || true
sed -n '/^=== Q5S/,$p' $TMP/summary.txt | grep -v '^===' > $TMP/q5s.txt || true
diff $TMP/q4.txt $TMP/q4s.txt > /dev/null || fail "Q4S returns different rows from Q4"
diff $TMP/q5.txt $TMP/q5s.txt > /dev/null || fail "Q5S returns different rows from Q5"
differing=$(psql_db -tA -c "SELECT count(*) FROM ((SELECT student_id, units_taken, cgpa FROM student_standing EXCEPT SELECT student_id, units_taken, cgpa FROM student_cgpa)
                                                 UNION ALL (SELECT student_id, units_taken, cgpa FROM student_cgpa EXCEPT SELECT student_id, units_taken, cgpa FROM student_standing)) d")
[ "$differing" = 0 ] || fail "the standing differs from the live CGPAs for $differing students"
{ echo "Q4S vs Q4 on the full data: $(wc -l < $TMP/q4.txt | tr -d ' ') rows, identical"
  echo "Q5S vs Q5 on the full data: $(wc -l < $TMP/q5.txt | tr -d ' ') rows, identical"
  echo "Every student's stored standing vs the live CGPA view: $differing rows differ (both directions)"
} > $E/Olayinka_Egbedokun_summary_check.txt
plans $P2/Olayinka_Egbedokun_queries_summary.sql plans_summary_noindex
psql_db < $P2/Olayinka_Egbedokun_summary_indexes.sql > /dev/null
plans $P2/Olayinka_Egbedokun_queries_summary.sql plans_summary_indexed
psql_db -c "SELECT relname AS index_name, pg_size_pretty(pg_relation_size(oid)) AS size FROM pg_class
            WHERE relname IN ('uq_standing_student', 'ix_standing_programme_cgpa', 'ix_standing_cgpa', 'student_standing') ORDER BY relname" \
  > $E/Olayinka_Egbedokun_summary_sizes.txt

echo "5. Refresh cost and staleness..."
psql_db > $E/Olayinka_Egbedokun_refresh_cost.txt <<'SQL'
\timing on
\echo '=== Refresh with its three indexes, then without them (indexes dropped inside a rolled-back transaction), alternating, 3 rounds'
\echo 'round 1 with'
REFRESH MATERIALIZED VIEW student_standing;
BEGIN; DROP INDEX uq_standing_student, ix_standing_programme_cgpa, ix_standing_cgpa;
\echo 'round 1 without'
REFRESH MATERIALIZED VIEW student_standing;
ROLLBACK;
BEGIN; DROP INDEX uq_standing_student, ix_standing_programme_cgpa, ix_standing_cgpa;
\echo 'round 2 without'
REFRESH MATERIALIZED VIEW student_standing;
ROLLBACK;
\echo 'round 2 with'
REFRESH MATERIALIZED VIEW student_standing;
\echo 'round 3 with'
REFRESH MATERIALIZED VIEW student_standing;
BEGIN; DROP INDEX uq_standing_student, ix_standing_programme_cgpa, ix_standing_cgpa;
\echo 'round 3 without'
REFRESH MATERIALIZED VIEW student_standing;
ROLLBACK;
SQL
awk '/^round [0-9] (with|without)$/ {k = $3} k && /^Time:/ {v[k] = v[k] " " $2; n[k]++; s[k, n[k]] = $2; k = ""}
     function med(k,   a, b, c) { a = s[k,1]; b = s[k,2]; c = s[k,3]; return (a <= b) ? ((b <= c) ? b : ((a <= c) ? c : a)) : ((a <= c) ? a : ((b <= c) ? c : b)) }
     END { print "refresh_ms_with:" v["with"] "  (median " med("with") ")"; print "refresh_ms_without:" v["without"] "  (median " med("without") ")" }' \
  $E/Olayinka_Egbedokun_refresh_cost.txt > $E/Olayinka_Egbedokun_refresh_cost_summary.txt
psql_db > $E/Olayinka_Egbedokun_staleness.txt <<'SQL'
\echo '=== A correction is made after the last refresh (inside a transaction that is rolled back)'
BEGIN;
INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
SELECT r.result_id, CASE WHEN r.score >= 40 THEN 0 ELSE 100 END,   -- always changes the grade
       'Staleness demonstration, rolled back', d.head_lecturer_id
FROM results r JOIN registrations g USING (registration_id) JOIN students s USING (student_id)
JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id) JOIN departments d USING (department_id)
WHERE s.matric_no = 'WU/2024/2001' AND c.code = 'CSC211';
\echo '=== Students whose stored CGPA no longer matches the live one (one correction was made, so expect 1)'
SELECT 'stale_before_refresh=' || count(*) AS result FROM student_standing st JOIN student_cgpa c USING (student_id) WHERE st.cgpa <> c.cgpa;
REFRESH MATERIALIZED VIEW student_standing;
\echo '=== The same check after a refresh'
SELECT 'stale_after_refresh=' || count(*) AS result FROM student_standing st JOIN student_cgpa c USING (student_id) WHERE st.cgpa <> c.cgpa;
ROLLBACK;
SQL
grep -q 'stale_before_refresh=1$' $E/Olayinka_Egbedokun_staleness.txt || fail "staleness: the correction should make exactly one student stale"
grep -q 'stale_after_refresh=0$' $E/Olayinka_Egbedokun_staleness.txt || fail "staleness: a refresh should clear it"

echo "6. Results table and document check..."
{
  echo "| Query | Stage | Buffers | Median total (ms) |"
  echo "|---|---|---|---|"
  for stage in baseline without_indexes jit_off summary_noindex summary_indexed; do
    awk -v s="$stage" 'NR > 1 { printf "| %s | %s | %d | %.2f |\n", $1, s, $6, $5 }' $E/Olayinka_Egbedokun_plans_${stage}_summary.txt
  done
} > $E/Olayinka_Egbedokun_results_table.md
buf() { awk -v q="$2" '$1 == q {print $6}' $E/Olayinka_Egbedokun_plans_$1_summary.txt; }
{
  claim() { if grep -qF -- "$2" "$1"; then echo "OK    $1: \"$2\""; else echo "WRONG $1: expected \"$2\""; fi; }
  # Every "buffers" figure written in the analysis is written as "N buffers (Qx, stage)".
  tr '\n' ' ' < $P2/Olayinka_Egbedokun_analysis.md | tr -s ' ' | grep -oE '[0-9,]+ buffers \(Q[0-9]S?, [a-z_]+\)' | sort -u | while read -r n _ q st; do
    n=${n//,/}; q=${q#(}; q=${q%,}; st=${st%)}
    actual=$(buf "$st" "$q")
    if [ "$n" = "$actual" ]; then echo "OK    analysis: $q $st = $n buffers"; else echo "WRONG analysis: $q $st says $n buffers, evidence has $actual"; fi
  done
  claim $P2/README.md "${n_students:0:${#n_students}-3},${n_students: -3} students"
  claim $P2/Olayinka_Egbedokun_analysis.md "${n_results:0:${#n_results}-3},${n_results: -3} approved results"
} > $E/Olayinka_Egbedokun_doc_claims_check.txt
if grep -q '^WRONG' $E/Olayinka_Egbedokun_doc_claims_check.txt; then cat $E/Olayinka_Egbedokun_doc_claims_check.txt >&2; fail "a document states something the evidence does not"; fi
echo "   $(grep -c '^OK' $E/Olayinka_Egbedokun_doc_claims_check.txt) document checks OK"
echo "Portfolio 2 evidence regenerated in $E/"
