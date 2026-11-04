-- Scenario 3, session A (the registry): read Zainab's CGPA twice in one
-- transaction at isolation level :level, two seconds apart. Session B
-- (Olayinka_Egbedokun_s3_correction.sql) commits a result correction in
-- between. Run by the reproduce script with -v level='READ COMMITTED' or
-- -v level='REPEATABLE READ'.

\set QUIET on
\pset tuples_only on
\pset format unaligned
BEGIN ISOLATION LEVEL :level;
SELECT 'A: first read,  CGPA = ' || cgpa FROM student_cgpa
WHERE student_id = (SELECT student_id FROM students WHERE matric_no = 'WU/2023/0003');
SELECT pg_sleep(2);
SELECT 'A: second read, CGPA = ' || cgpa FROM student_cgpa
WHERE student_id = (SELECT student_id FROM students WHERE matric_no = 'WU/2023/0003');
COMMIT;
