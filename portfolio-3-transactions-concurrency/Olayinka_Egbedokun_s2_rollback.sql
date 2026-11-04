-- Scenario 2: ROLLBACK, three ways. Run with ON_ERROR_STOP off, so the
-- errors are shown instead of stopping the script.
--   2a  explicit ROLLBACK: the work is undone on request;
--   2b  a failure part-way: the database aborts the whole transaction, so
--       the statements that had succeeded are undone too (atomicity);
--   2c  a SAVEPOINT: only the failed step is undone, the rest commits.

\set reg_sql 'INSERT INTO registrations (student_id, offering_id) SELECT s.student_id, o.offering_id FROM students s, course_offerings o JOIN courses c USING (course_id) JOIN semesters m USING (semester_id) JOIN academic_sessions a USING (session_id) WHERE a.name = ''2024/2025'' AND m.term = ''first'''

\echo '--- 2a. Yusuf registers for CSC211 and CSC213, then the transaction is rolled back'
BEGIN;
:reg_sql AND s.matric_no = 'WU/2023/0006' AND c.code IN ('CSC211', 'CSC213');
ROLLBACK;

\echo '--- 2b. Kelechi registers for five courses in one transaction; the fifth (CSC219) breaks the 24-unit limit'
BEGIN;
:reg_sql AND s.matric_no = 'WU/2023/0004' AND c.code = 'CSC211';
:reg_sql AND s.matric_no = 'WU/2023/0004' AND c.code = 'CSC213';
:reg_sql AND s.matric_no = 'WU/2023/0004' AND c.code = 'CSC215';
:reg_sql AND s.matric_no = 'WU/2023/0004' AND c.code = 'CSC217';
:reg_sql AND s.matric_no = 'WU/2023/0004' AND c.code = 'CSC219';
\echo '--- the transaction is now aborted: even a read is refused until it ends'
SELECT count(*) FROM registrations;
COMMIT;
\echo '--- (COMMIT of an aborted transaction is turned into ROLLBACK, as the line above shows)'

\echo '--- 2c. Ngozi does the same, but sets a savepoint before the fifth course'
BEGIN;
:reg_sql AND s.matric_no = 'WU/2023/0005' AND c.code = 'CSC211';
:reg_sql AND s.matric_no = 'WU/2023/0005' AND c.code = 'CSC213';
:reg_sql AND s.matric_no = 'WU/2023/0005' AND c.code = 'CSC215';
:reg_sql AND s.matric_no = 'WU/2023/0005' AND c.code = 'CSC217';
SAVEPOINT before_fifth;
:reg_sql AND s.matric_no = 'WU/2023/0005' AND c.code = 'CSC219';
ROLLBACK TO SAVEPOINT before_fifth;
COMMIT;
