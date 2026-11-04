-- Wavers University — Portfolio 2: realistic volume
--
-- Run after Olayinka_Egbedokun_seed.sql. Adds 4,000 students (1,000 per
-- programme, entering in 2024/2025) and 96 courses (24 per department), then
-- runs four semesters: each student takes the six courses of their
-- department for their level and term. That is 96,000 registrations, each
-- with an approved result. Scores come from a hash of the student and
-- course, so every run produces identical data: about 8% of students are
-- struggling (scores 10.00-50.00, so most are on probation), the rest score
-- 30.00-100.00.
--
-- Everything goes through the Portfolio 1 rules: the registration, result
-- and approval triggers run on every row. One student's transcript is then
-- 24 of about 96,000 results, the proportion a real portal works with.

\timing on

INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
SELECT 'WU/2024/' || lpad(i::text, 4, '0'), 'Student', 'S' || lpad(i::text, 4, '0'),
       'student' || i || '@student.wavers.edu.ng',
       (SELECT programme_id FROM programmes ORDER BY programme_id OFFSET (i - 1) % 4 LIMIT 1),
       (SELECT session_id FROM academic_sessions WHERE name = '2024/2025')
FROM generate_series(1, 4000) AS i;

-- Course codes: department + level digit + term digit (1 first, 2 second) +
-- number, e.g. CSC111 to CSC116 are the 100-level first-term courses.
INSERT INTO courses (department_id, code, title, units, level, term)
SELECT d.department_id,
       d.code || lv || CASE t WHEN 'first' THEN '1' ELSE '2' END || n,
       d.name || ' ' || lv || CASE t WHEN 'first' THEN '1' ELSE '2' END || n,
       3, lv * 100, t
FROM departments d
CROSS JOIN (VALUES (1), (2)) AS l(lv)
CROSS JOIN (VALUES ('first'), ('second')) AS tt(t)
CROSS JOIN generate_series(1, 6) AS n;

CREATE FUNCTION pg_temp.run_bulk_semester(p_session text, p_term text, p_level int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_sem integer;
BEGIN
    SELECT semester_id INTO v_sem FROM semesters JOIN academic_sessions USING (session_id)
    WHERE name = p_session AND term = p_term;
    UPDATE semesters SET status = 'registration_open' WHERE semester_id = v_sem;
    INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
    SELECT c.course_id, v_sem, l.lecturer_id, 1100
    FROM courses c
    JOIN lecturers l ON l.department_id = c.department_id AND l.staff_no LIKE '%2'
    WHERE c.level = p_level AND c.term = p_term AND c.code ~ '^[A-Z]{3}[12][12][1-6]$';
    INSERT INTO registrations (student_id, offering_id)
    SELECT s.student_id, o.offering_id
    FROM students s
    JOIN programmes p       ON p.programme_id = s.programme_id
    JOIN courses c          ON c.department_id = p.department_id AND c.level = p_level AND c.term = p_term
    JOIN course_offerings o ON o.course_id = c.course_id AND o.semester_id = v_sem
    WHERE s.matric_no LIKE 'WU/2024/%'
    ORDER BY s.student_id, c.code;
    UPDATE semesters SET status = 'teaching' WHERE semester_id = v_sem;
    UPDATE semesters SET status = 'grading'  WHERE semester_id = v_sem;
    INSERT INTO results (registration_id, score, entered_by)
    SELECT g.registration_id,
           CASE WHEN abs(hashtext(s.matric_no || 'band')::bigint) % 100 < 8
                THEN 10 + (abs(hashtext(s.matric_no || c.code)::bigint) % 4001) / 100.0
                ELSE 30 + (abs(hashtext(s.matric_no || c.code)::bigint) % 7001) / 100.0 END,
           o.lecturer_id
    FROM registrations g
    JOIN course_offerings o ON o.offering_id = g.offering_id AND o.semester_id = v_sem
    JOIN courses c          ON c.course_id = o.course_id
    JOIN students s         ON s.student_id = g.student_id;
    UPDATE results r SET status = 'submitted'
    FROM registrations g JOIN course_offerings o USING (offering_id)
    WHERE g.registration_id = r.registration_id AND o.semester_id = v_sem;
    UPDATE results r SET status = 'approved', approved_by = d.head_lecturer_id
    FROM registrations g JOIN course_offerings o USING (offering_id)
         JOIN courses c USING (course_id) JOIN departments d USING (department_id)
    WHERE g.registration_id = r.registration_id AND o.semester_id = v_sem;
    -- About 1 in 100 approved results is corrected (+5 marks) by the head.
    INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
    SELECT r.result_id, r.score + 5, 'Re-mark after script review', d.head_lecturer_id
    FROM results r
    JOIN registrations g    ON g.registration_id = r.registration_id
    JOIN course_offerings o ON o.offering_id = g.offering_id AND o.semester_id = v_sem
    JOIN courses c          ON c.course_id = o.course_id
    JOIN departments d      ON d.department_id = c.department_id
    JOIN students s         ON s.student_id = g.student_id
    WHERE abs(hashtext(s.matric_no || c.code || 'amend')::bigint) % 100 = 0 AND r.score <= 95;
    UPDATE semesters SET status = 'closed' WHERE semester_id = v_sem;
END $$;

SELECT pg_temp.run_bulk_semester('2024/2025', 'first',  100);
SELECT pg_temp.run_bulk_semester('2024/2025', 'second', 100);
SELECT pg_temp.run_bulk_semester('2025/2026', 'first',  200);
SELECT pg_temp.run_bulk_semester('2025/2026', 'second', 200);

-- Each status change is an UPDATE, which under MVCC leaves the old row
-- version behind. VACUUM (FULL) rewrites the tables without them, so plans
-- read only live data; the plain VACUUM then sets the visibility map that
-- index-only scans rely on. ANALYZE then reads every row (target 1000 means
-- samples of up to 300,000 rows, more than any table here), so the planner's
-- statistics, and with them its plans, are the same on every rebuild.
VACUUM (FULL) results, registrations, course_offerings, students, semesters;
VACUUM;
SET default_statistics_target = 1000;
ANALYZE;

\timing off
