#!/usr/bin/env bash
# Wavers University — Portfolio 4: build the MongoDB model from PostgreSQL and check it
#
#   bash portfolio-4-nosql/Olayinka_Egbedokun_reproduce.sh
#
# 1. PostgreSQL (the source of truth): P1 schema, P2 seed and bulk load.
# 2. MongoDB: student_records with its validator; one document per student,
#    exported from PostgreSQL and imported; the validator must reject a bad
#    document.
# 3. M1-M4 in MongoDB must give exactly PostgreSQL's answers.
# 4. M2/M3 explained without and with indexes: fewer documents examined.
# 5. M5, a correction: made in PostgreSQL, the MongoDB copy is stale until
#    that student's document is re-exported, then matches again.
# Any check that fails stops the run.

set -euo pipefail
cd "$(dirname "$0")/.."
P4=portfolio-4-nosql
E=$P4/evidence
mkdir -p "$E"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
DB=wavers_p4
MATRIC=WU/2024/2001; PROGRAMME=CSC-BSC; COURSE=CSC211
PARAMS="const P = { matric: '$MATRIC', programme: '$PROGRAMME', course: '$COURSE' };"

pg() { docker exec -i wu-postgres psql -U wavers -X -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
mongo() { docker exec -i wu-mongo mongosh --quiet -u wavers -p "${MONGO_PASSWORD:-wavers_local_only}" --authenticationDatabase admin wavers "$@"; }
mongo_file() { mongo --eval "$PARAMS $(cat "$1")"; }
fail() { echo "CHECK FAILED: $*" >&2; exit 1; }

docker compose up -d --wait --quiet-pull > /dev/null 2>&1 || fail "could not start the containers (is Docker running?)"
pinned=$(sed -n 's/^ *image: mongo:\([0-9.]*\) *$/\1/p' compose.yml)
running=$(mongo --eval 'print(db.version())')
[ "$running" = "$pinned" ] || fail "MongoDB is '$running', compose.yml pins '$pinned'"
{ echo "MongoDB $running (Docker image $(docker inspect -f '{{.Config.Image}}' wu-mongo))"
  echo "PostgreSQL $(docker exec wu-postgres psql -U wavers -tAc 'SHOW server_version') (Docker image $(docker inspect -f '{{.Config.Image}}' wu-postgres))"
} > $E/Olayinka_Egbedokun_environment.txt

echo "1. PostgreSQL source data (about a minute)..."
docker exec -i wu-postgres psql -U wavers -X -q -d wavers -c "DROP DATABASE IF EXISTS $DB WITH (FORCE)" -c "CREATE DATABASE $DB" 2> /dev/null
pg -q < portfolio-1-database-design/Olayinka_Egbedokun_schema.sql > /dev/null
pg -q < portfolio-2-query-optimisation/Olayinka_Egbedokun_seed.sql > /dev/null
pg -q < portfolio-2-query-optimisation/Olayinka_Egbedokun_bulk_load.sql > /dev/null
students=$(pg -tAc "SELECT count(*) FROM students")

echo "2. MongoDB collection, import and validator..."
mongo_file $P4/Olayinka_Egbedokun_collection.js > $E/Olayinka_Egbedokun_collection_run.txt
pg < $P4/Olayinka_Egbedokun_export.sql > $TMP/records.json
docker exec -i wu-mongo mongoimport -u wavers -p "${MONGO_PASSWORD:-wavers_local_only}" --authenticationDatabase admin \
  --db wavers --collection student_records < $TMP/records.json > $E/Olayinka_Egbedokun_import_run.txt 2>&1
docs=$(mongo --eval 'print(db.student_records.countDocuments())')
[ "$docs" = "$students" ] || fail "imported $docs documents, PostgreSQL has $students students"
{ echo "Students in PostgreSQL: $students; documents in MongoDB: $docs"
  echo "Average document size: $(mongo --eval 'print(Math.round(db.student_records.stats().avgObjSize))') bytes"
  echo
  echo "One document (the student used in M1), as stored:"
  mongo --eval "printjson(db.student_records.findOne({_id: '$MATRIC'}))"
} > $E/Olayinka_Egbedokun_sample_document.txt
mongo_file $P4/Olayinka_Egbedokun_validator_test.js > $E/Olayinka_Egbedokun_validator_test.txt
[ "$(grep -c ': REJECTED: code 121 ' $E/Olayinka_Egbedokun_validator_test.txt)" = 2 ] || fail "the validator should reject both bad documents (code 121)"

echo "3. M1-M4 in MongoDB vs PostgreSQL..."
mongo_file $P4/Olayinka_Egbedokun_queries.js > $E/Olayinka_Egbedokun_mongo_answers.txt
pg -v matric="$MATRIC" -v programme="$PROGRAMME" -v course="$COURSE" < $P4/Olayinka_Egbedokun_pg_answers.sql > $E/Olayinka_Egbedokun_pg_answers.txt
{ for m in "M1 transcript" "M2 dean's list" "M3 failed $COURSE" "M4 totals" "M4 stored cgpa"; do
    n=$(sed -n "/^=== $m\$/,/^===/p" $E/Olayinka_Egbedokun_pg_answers.txt | grep -vc '^===' || true)
    echo "$m: $n rows in each"
  done
  diff $E/Olayinka_Egbedokun_pg_answers.txt $E/Olayinka_Egbedokun_mongo_answers.txt && echo "MongoDB and PostgreSQL answers: IDENTICAL"
} > $E/Olayinka_Egbedokun_answers_check.txt || fail "MongoDB and PostgreSQL answers differ (see answers_check)"

echo "4. Indexes: M2 and M3 explained before and after..."
{ mongo --eval "const P = { programme: '$PROGRAMME', course: '$COURSE', phase: 'without indexes' }; $(cat $P4/Olayinka_Egbedokun_explain.js)"
  mongo_file $P4/Olayinka_Egbedokun_indexes.js > /dev/null
  mongo --eval "const P = { programme: '$PROGRAMME', course: '$COURSE', phase: 'with indexes' }; $(cat $P4/Olayinka_Egbedokun_explain.js)"
} > $E/Olayinka_Egbedokun_explain.txt
docs_of() { sed -n "s/^$1 $2|docsExamined=\([0-9]*\)|.*/\1/p" $E/Olayinka_Egbedokun_explain.txt; }
returned_of() { sed -n "s/^$1 $2|.*|returned=\([0-9]*\)|.*/\1/p" $E/Olayinka_Egbedokun_explain.txt; }
for q in M2 M3; do
  [ "$(docs_of $q 'without indexes')" = "$docs" ] || fail "$q without indexes should examine every document"
  [ "$(docs_of $q 'with indexes')" -le "$(returned_of $q 'with indexes')" ] || fail "$q with its index should examine no more documents than it returns"
done
grep -q '^M2 with indexes|.*IXSCAN(programme_cgpa)' $E/Olayinka_Egbedokun_explain.txt || fail "M2 should use programme_cgpa"
grep -q '^M3 with indexes|.*IXSCAN(course_grade)' $E/Olayinka_Egbedokun_explain.txt || fail "M3 should use course_grade"

echo "5. A correction: PostgreSQL first, then the MongoDB copy..."
cgpa_pg() { pg -tAc "SELECT cgpa FROM student_cgpa WHERE student_id = (SELECT student_id FROM students WHERE matric_no = '$MATRIC')"; }
cgpa_mongo() { mongo --eval "print(db.student_records.findOne({_id: '$MATRIC'}).cgpa.toString())"; }
before=$(cgpa_pg)
pg -q -c "INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
          SELECT r.result_id, CASE WHEN r.score >= 40 THEN 0 ELSE 100 END, 'Correction for the P4 demonstration', d.head_lecturer_id
          FROM results r JOIN registrations g USING (registration_id) JOIN students s USING (student_id)
          JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id) JOIN departments d USING (department_id)
          WHERE s.matric_no = '$MATRIC' AND c.code = '$COURSE'"
after_pg=$(cgpa_pg); stale=$(cgpa_mongo)
pg -v only="$MATRIC" < $P4/Olayinka_Egbedokun_export.sql > $TMP/one.json
docker exec -i wu-mongo mongoimport -u wavers -p "${MONGO_PASSWORD:-wavers_local_only}" --authenticationDatabase admin \
  --db wavers --collection student_records --mode upsert < $TMP/one.json > /dev/null 2>&1
refreshed=$(cgpa_mongo)
{ echo "Correction committed in PostgreSQL for $MATRIC, $COURSE (an amendment, as Portfolio 1 requires)."
  echo "CGPA in PostgreSQL before: $before; after: $after_pg"
  echo "CGPA in the MongoDB copy right after the correction: $stale (stale)"
  echo "CGPA in the MongoDB copy after re-exporting that one student: $refreshed"
} > $E/Olayinka_Egbedokun_correction.txt
[ "$after_pg" != "$before" ] && [ "$stale" = "$before" ] && [ "$refreshed" = "$after_pg" ] || fail "correction: expected the copy to be stale, then refreshed (see correction)"

echo "6. The README's figures against the evidence..."
fmt() { if [ ${#1} -gt 3 ]; then echo "${1:0:${#1}-3},${1: -3}"; else echo "$1"; fi; }
rows() { sed -n "/^=== $1\$/,/^===/p" $E/Olayinka_Egbedokun_pg_answers.txt | grep -vc '^===' || true; }
{ claim() { if grep -qF -- "$1" $P4/README.md; then echo "OK    \"$1\""; else echo "WRONG expected \"$1\""; fi; }
  claim "all $(fmt "$docs")"
  claim "| $(rows 'M1 transcript') |"
  claim "| $(rows "M2 dean's list") |"
  claim "| $(rows "M3 failed $COURSE") |"
  claim "| $(fmt "$(rows 'M4 totals')") each |"
  claim "$(fmt "$(docs_of M2 'without indexes')") → $(docs_of M2 'with indexes'):"
  claim "$(fmt "$(docs_of M3 'without indexes')") → $(docs_of M3 'with indexes'):"
} > $E/Olayinka_Egbedokun_doc_claims_check.txt
grep -q '^WRONG' $E/Olayinka_Egbedokun_doc_claims_check.txt && { cat $E/Olayinka_Egbedokun_doc_claims_check.txt >&2; fail "the README states something the evidence does not"; }

echo "All checks passed; evidence in $E/"
