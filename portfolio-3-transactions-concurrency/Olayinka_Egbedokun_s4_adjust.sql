-- Scenario 4: one session adjusting a student's DRAFT CSC311 score the way
-- an application often does: read the score, compute, write it back.
-- Two of these run at once on the same score (the reproduce script):
--   the lecturer adds 5 bonus marks, pausing 2 s between read and write;
--   the head adds 3 moderation marks, starting 1 s later, with no pause.
-- Variables:
--   who      'lecturer' or 'head' (for the log)
--   matric   the student
--   add      marks to add
--   pause    seconds between read and write
--   level    isolation level
--   lock     '' (plain read) or 'FOR UPDATE' (lock the row when reading)

\set QUIET on
\pset tuples_only on
\pset format unaligned
BEGIN ISOLATION LEVEL :level;
SELECT clock_timestamp() AS t0 \gset
SELECT r.result_id AS rid, r.score AS current
FROM results r JOIN registrations g USING (registration_id) JOIN students s USING (student_id)
JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id)
WHERE s.matric_no = :'matric' AND c.code = 'CSC311'
:lock \gset
SELECT :'who' || ': read score ' || :current || ' after waiting '
       || round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz)::numeric, 1) || ' s';
SELECT pg_sleep(:pause);
UPDATE results SET score = :current + :add WHERE result_id = :rid;
SELECT :'who' || ': wrote score ' || (:current + :add);
COMMIT;
