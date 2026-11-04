-- Scenario 1: COMMIT. Amaka registers for three courses as one unit of work.
-- A transaction makes several changes take effect together: until COMMIT,
-- no other session sees any of them; after COMMIT, every session sees all.

\echo '--- Amaka registers for CSC211, CSC213 and CSC219 in one transaction'
BEGIN;
INSERT INTO registrations (student_id, offering_id)
SELECT s.student_id, o.offering_id
FROM students s, course_offerings o JOIN courses c USING (course_id)
JOIN semesters m USING (semester_id) JOIN academic_sessions a USING (session_id)
WHERE s.matric_no = 'WU/2023/0001' AND a.name = '2024/2025' AND m.term = 'first'
  AND c.code IN ('CSC211', 'CSC213', 'CSC219');
COMMIT;
