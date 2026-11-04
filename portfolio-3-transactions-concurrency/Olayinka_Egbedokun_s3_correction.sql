-- Scenario 3, session B (the head of Computer Science): one second after A
-- starts, correct Zainab's approved CSC101 score to :score and commit.

\set QUIET on
\pset tuples_only on
\pset format unaligned
INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
SELECT r.result_id, :score, 'Re-mark after appeal', d.head_lecturer_id
FROM results r
JOIN registrations g    USING (registration_id)
JOIN students s         USING (student_id)
JOIN course_offerings o USING (offering_id)
JOIN courses c          USING (course_id)
JOIN departments d      USING (department_id)
WHERE s.matric_no = 'WU/2023/0003' AND c.code = 'CSC101';
SELECT 'B: committed CSC101 correction to ' || :score;
