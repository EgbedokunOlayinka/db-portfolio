-- Wavers University — Portfolio 5: the head of Computer Science corrects
-- Zainab's approved CSC101 score (a Portfolio 1 amendment) and reports how
-- long the commit took to return. Run by the reproduce script with
-- -v score=<new score> -v mode=<synchronous_commit setting>.

\set QUIET on
\pset tuples_only on
\pset format unaligned
SET application_name = 'p5_writer';
SET synchronous_commit = :mode;
SELECT clock_timestamp() AS t0 \gset
INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
SELECT r.result_id, :score, 'Re-mark after appeal', d.head_lecturer_id
FROM results r
JOIN registrations g    USING (registration_id)
JOIN students s         USING (student_id)
JOIN course_offerings o USING (offering_id)
JOIN courses c          USING (course_id)
JOIN departments d      USING (department_id)
WHERE s.matric_no = 'WU/2023/0003' AND c.code = 'CSC101';
SELECT 'correction to ' || :score || ' committed (synchronous_commit = ' || current_setting('synchronous_commit')
       || '); the commit returned after '
       || round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz)::numeric, 1) || ' s';
