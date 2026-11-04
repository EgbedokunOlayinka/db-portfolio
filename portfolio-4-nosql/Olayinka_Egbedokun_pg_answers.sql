-- Wavers University — Portfolio 4: the same questions answered by PostgreSQL
--
-- The reproduce script compares this output with Olayinka_Egbedokun_queries.js
-- line by line. Matric numbers are sorted with COLLATE "C" (byte order),
-- which is how MongoDB orders strings.

\set QUIET on
\pset tuples_only on
\pset format unaligned
\pset fieldsep '|'

\echo '=== M1 transcript'
SELECT session, term, code, score, grade FROM transcript
WHERE matric_no = :'matric' ORDER BY starts_on, term, code;

\echo '=== M2 dean''s list'
SELECT s.matric_no, c.cgpa FROM student_cgpa c JOIN students s USING (student_id) JOIN programmes p USING (programme_id)
WHERE p.code = :'programme' ORDER BY c.cgpa DESC, s.matric_no COLLATE "C" LIMIT 10;

\echo '=== M3 failed' :course
SELECT DISTINCT s.matric_no COLLATE "C" FROM graded_courses gc JOIN students s USING (student_id)
WHERE gc.code = :'course' AND gc.grade = 'F' ORDER BY 1;

\echo '=== M4 totals'
SELECT s.matric_no, sum(gc.points * gc.units), sum(gc.units)
FROM graded_courses gc JOIN students s USING (student_id)
GROUP BY s.matric_no ORDER BY s.matric_no COLLATE "C";

\echo '=== M4 stored cgpa'
SELECT s.matric_no, c.cgpa FROM students s LEFT JOIN student_cgpa c USING (student_id)
ORDER BY s.matric_no COLLATE "C";
