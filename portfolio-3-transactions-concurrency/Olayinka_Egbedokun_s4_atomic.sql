-- Scenario 4d: the same adjustment done by the database in one statement.
-- UPDATE ... SET score = score + :add reads and writes in one step. At READ
-- COMMITTED, an UPDATE that finds the row locked by another transaction
-- waits for it to finish, then re-reads the newest committed version before
-- applying its change, so no change is lost. (At REPEATABLE READ the same
-- statement would fail with a serialization error instead.)
-- Variables: who, matric, add, pause (seconds to hold the transaction open).

\set QUIET on
\pset tuples_only on
\pset format unaligned
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT clock_timestamp() AS t0 \gset
UPDATE results SET score = score + :add
WHERE result_id = (SELECT r.result_id FROM results r JOIN registrations g USING (registration_id)
                   JOIN students s USING (student_id) JOIN course_offerings o USING (offering_id)
                   JOIN courses c USING (course_id)
                   WHERE s.matric_no = :'matric' AND c.code = 'CSC311')
RETURNING :'who' || ': score is now ' || score || ' after waiting '
          || round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz)::numeric, 1) || ' s';
SELECT pg_sleep(:pause);
COMMIT;
