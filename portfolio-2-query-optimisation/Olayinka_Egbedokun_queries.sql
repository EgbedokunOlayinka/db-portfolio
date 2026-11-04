-- Wavers University — Portfolio 2: the five workload queries
--
-- Prints results by default. With -v EXPLAIN='EXPLAIN (ANALYZE, BUFFERS)'
-- it prints each query's execution plan instead, so the queries measured
-- are exactly the queries checked. Parameters (psql variables, defaults
-- below): matric, course, session, term, programme.

\if :{?EXPLAIN} \else \set EXPLAIN '' \endif
\if :{?matric} \else \set matric 'WU/2023/0003' \endif
\if :{?course} \else \set course 'PHY101' \endif
\if :{?session} \else \set session '2023/2024' \endif
\if :{?term} \else \set term 'first' \endif
\if :{?programme} \else \set programme 'CSC-BSC' \endif

\echo '=== Q1. Transcript of one student'
:EXPLAIN
SELECT session, term, code, title, units, score, grade, points, amended
FROM transcript
WHERE matric_no = :'matric'
ORDER BY starts_on, term, code;

\echo '=== Q2. Semester GPA and CGPA of one student'
:EXPLAIN
SELECT a.name AS session, m.term, g.units_taken, g.units_passed, g.gpa, c.cgpa
FROM semester_gpa g
JOIN semesters m         ON m.semester_id = g.semester_id
JOIN academic_sessions a ON a.session_id = m.session_id
JOIN student_cgpa c      ON c.student_id = g.student_id
WHERE g.student_id = (SELECT student_id FROM students WHERE matric_no = :'matric')
ORDER BY a.starts_on, m.term;

\echo '=== Q3. Result sheet of one course offering (every registered student)'
:EXPLAIN
SELECT s.matric_no, s.last_name || ', ' || s.first_name AS student_name,
       coalesce(e.score, r.score) AS score, gs.grade, r.status,
       coalesce(e.amended, false) AS amended
FROM course_offerings o
JOIN courses c           ON c.course_id = o.course_id
JOIN semesters m         ON m.semester_id = o.semester_id
JOIN academic_sessions a ON a.session_id = m.session_id
JOIN registrations g     ON g.offering_id = o.offering_id AND g.status = 'registered'
JOIN students s          ON s.student_id = g.student_id
LEFT JOIN results r      ON r.registration_id = g.registration_id
LEFT JOIN effective_results e ON e.result_id = r.result_id
LEFT JOIN grade_scale gs ON coalesce(e.score, r.score) <@ gs.score_range
WHERE c.code = :'course' AND a.name = :'session' AND m.term = :'term'
ORDER BY s.matric_no;

\echo '=== Q4. Dean''s list: top 10 CGPAs in one programme'
:EXPLAIN
SELECT s.matric_no, s.last_name || ', ' || s.first_name AS student_name, c.units_taken, c.cgpa
FROM student_cgpa c
JOIN students s   ON s.student_id = c.student_id
JOIN programmes p ON p.programme_id = s.programme_id
WHERE p.code = :'programme'
ORDER BY c.cgpa DESC, s.matric_no
LIMIT 10;

\echo '=== Q5. Probation list: every student with CGPA below 1.50'
:EXPLAIN
SELECT s.matric_no, p.code AS programme, c.units_taken, c.cgpa
FROM student_cgpa c
JOIN students s   ON s.student_id = c.student_id
JOIN programmes p ON p.programme_id = s.programme_id
WHERE c.cgpa < 1.50
ORDER BY c.cgpa, s.matric_no;
