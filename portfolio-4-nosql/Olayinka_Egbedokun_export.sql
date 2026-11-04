-- Wavers University — Portfolio 4: export each student's record as one JSON document
--
-- Runs on the PostgreSQL database (the source of truth) and prints one
-- MongoDB Extended JSON document per line, ready for mongoimport. Scores,
-- GPAs and CGPAs are exported as exact decimals ($numberDecimal) and counts
-- as 32-bit integers ($numberInt), so nothing is rounded on the way.
-- With -v only=<matric number>, exports just that student (used to refresh
-- one document after a correction).

\if :{?only} \else \set only '' \endif
\set QUIET on
\pset tuples_only on
\pset format unaligned

WITH course_docs AS (
    SELECT gc.student_id, gc.semester_id,
           jsonb_agg(jsonb_build_object(
               'code',    gc.code,
               'title',   gc.title,
               'units',   jsonb_build_object('$numberInt', gc.units::text),
               'score',   jsonb_build_object('$numberDecimal', gc.score::text),
               'grade',   gc.grade,
               'points',  jsonb_build_object('$numberInt', gc.points::text),
               'amended', gc.amended) ORDER BY gc.code) AS courses
    FROM graded_courses gc
    GROUP BY gc.student_id, gc.semester_id
),
semester_docs AS (
    SELECT c.student_id,
           jsonb_agg(jsonb_build_object(
               'session',    a.name,
               'term',       m.term,
               'unitsTaken', jsonb_build_object('$numberInt', g.units_taken::text),
               'gpa',        jsonb_build_object('$numberDecimal', g.gpa::text),
               'courses',    c.courses) ORDER BY a.starts_on, m.term) AS semesters
    FROM course_docs c
    JOIN semester_gpa g      ON g.student_id = c.student_id AND g.semester_id = c.semester_id
    JOIN semesters m         ON m.semester_id = c.semester_id
    JOIN academic_sessions a ON a.session_id = m.session_id
    GROUP BY c.student_id
)
SELECT jsonb_build_object(
           '_id',         s.matric_no,
           'name',        jsonb_build_object('first', s.first_name, 'last', s.last_name),
           'programme',   p.code,
           'status',      s.status,
           'semesters',   coalesce(sd.semesters, '[]'::jsonb),
           'unitsTaken',  jsonb_build_object('$numberInt', coalesce(cg.units_taken, 0)::text),
           'unitsPassed', jsonb_build_object('$numberInt', coalesce(cg.units_passed, 0)::text),
           'cgpa',        CASE WHEN cg.cgpa IS NULL THEN NULL
                               ELSE jsonb_build_object('$numberDecimal', cg.cgpa::text) END)
FROM students s
JOIN programmes p          ON p.programme_id = s.programme_id
LEFT JOIN semester_docs sd ON sd.student_id = s.student_id
LEFT JOIN student_cgpa cg  ON cg.student_id = s.student_id
WHERE :'only' = '' OR s.matric_no = :'only'
ORDER BY s.matric_no;
