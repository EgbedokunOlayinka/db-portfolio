-- Wavers University — Portfolio 2: small, hand-checkable seed
--
-- Run on a database built from the Portfolio 1 schema. Creates the Faculty
-- of Science (four departments, each with a head and a lecturer), one
-- programme per department, and six Computer Science students who take
-- seven courses over the 2023/2024 session. Every step goes through the P1
-- rules: semesters move through their stages, the course lecturer enters
-- the scores, the head of department approves them.
--
-- The expected query results are computed independently of SQL by
-- Olayinka_Egbedokun_seed_oracle.py (saved as Olayinka_Egbedokun_seed_expected.txt).

BEGIN;

INSERT INTO faculties (code, name) VALUES ('SCI', 'Faculty of Science');
INSERT INTO departments (faculty_id, code, name)
SELECT faculty_id, v.code, v.name FROM faculties,
       (VALUES ('CSC', 'Computer Science'), ('MTH', 'Mathematics'),
               ('PHY', 'Physics'), ('CHM', 'Chemistry')) AS v(code, name);

-- Per department: staff 00n1 is the head, 00n2 the lecturer who teaches.
INSERT INTO lecturers (department_id, staff_no, first_name, last_name, email)
SELECT d.department_id, v.staff_no, v.first_name, v.last_name, v.email
FROM (VALUES ('CSC', 'WU/STF/0011', 'Adaeze',  'Okafor',  'a.okafor@wavers.edu.ng'),
             ('CSC', 'WU/STF/0012', 'Bola',    'Adeyemi', 'b.adeyemi@wavers.edu.ng'),
             ('MTH', 'WU/STF/0021', 'Chidi',   'Eze',     'c.eze@wavers.edu.ng'),
             ('MTH', 'WU/STF/0022', 'Danjuma', 'Musa',    'd.musa@wavers.edu.ng'),
             ('PHY', 'WU/STF/0031', 'Efe',     'Ogun',    'e.ogun@wavers.edu.ng'),
             ('PHY', 'WU/STF/0032', 'Funke',   'Ade',     'f.ade@wavers.edu.ng'),
             ('CHM', 'WU/STF/0041', 'Gbenga',  'Ojo',     'g.ojo@wavers.edu.ng'),
             ('CHM', 'WU/STF/0042', 'Halima',  'Sani',    'h.sani@wavers.edu.ng'))
     AS v(dept, staff_no, first_name, last_name, email)
JOIN departments d ON d.code = v.dept;
UPDATE departments d SET head_lecturer_id = l.lecturer_id
FROM lecturers l WHERE l.department_id = d.department_id AND l.staff_no LIKE '%1';

INSERT INTO programmes (department_id, code, name, award, duration_years)
SELECT department_id, code || '-BSC', name, 'B.Sc.', 4 FROM departments;

INSERT INTO academic_sessions (name, starts_on, ends_on) VALUES
    ('2023/2024', '2023-09-18', '2024-08-30'),
    ('2024/2025', '2024-09-16', '2025-08-29'),
    ('2025/2026', '2025-09-15', '2026-08-28');
INSERT INTO semesters (session_id, term)
SELECT session_id, t FROM academic_sessions CROSS JOIN (VALUES ('first'), ('second')) AS v(t);

INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
SELECT v.m, v.f, v.l, lower(v.f || '.' || v.l) || '@student.wavers.edu.ng',
       (SELECT programme_id FROM programmes WHERE code = 'CSC-BSC'),
       (SELECT session_id FROM academic_sessions WHERE name = '2023/2024')
FROM (VALUES ('WU/2023/0001', 'Amaka', 'Nwosu'),  ('WU/2023/0002', 'Tunde', 'Bakare'),
             ('WU/2023/0003', 'Zainab', 'Bello'), ('WU/2023/0004', 'Kelechi', 'Obi'),
             ('WU/2023/0005', 'Ngozi', 'Eze'),    ('WU/2023/0006', 'Yusuf', 'Lawal')) AS v(m, f, l);

INSERT INTO courses (department_id, code, title, units, level, term)
SELECT d.department_id, v.code, v.title, v.units, 100, v.term
FROM (VALUES ('CSC', 'CSC101', 'Introduction to Computing',   3, 'first'),
             ('CSC', 'CSC103', 'Computing Laboratory',        2, 'first'),
             ('MTH', 'MTH101', 'Elementary Mathematics I',    3, 'first'),
             ('PHY', 'PHY101', 'General Physics I',           3, 'first'),
             ('CHM', 'CHM101', 'General Chemistry I',         2, 'first'),
             ('CSC', 'CSC102', 'Introduction to Programming', 3, 'second'),
             ('MTH', 'MTH102', 'Elementary Mathematics II',   3, 'second')) AS v(dept, code, title, units, term)
JOIN departments d ON d.code = v.dept;

-- Scores: student -> one score per course, in the order of the columns.
CREATE TEMP TABLE seed_scores (matric_no text, code text, score numeric(5,2));
INSERT INTO seed_scores
SELECT m, unnest(ARRAY['CSC101','CSC103','MTH101','PHY101','CHM101','CSC102','MTH102']), unnest(s)
FROM (VALUES ('WU/2023/0001', ARRAY[75, 68, 81, 72, 90, 77, 70]::numeric[]),
             ('WU/2023/0002', ARRAY[55, 61, 49.5, 58, 44, 62, 51]::numeric[]),
             ('WU/2023/0003', ARRAY[39.99, 45, 40, 30, 50, 35, 42]::numeric[]),
             ('WU/2023/0004', ARRAY[70, 69.99, 60, 59.99, 45, 49.99, 50]::numeric[]),
             ('WU/2023/0005', ARRAY[20, 38, 41, 10, 44.99, 25, 39.99]::numeric[]),
             ('WU/2023/0006', ARRAY[88, 92, 79, 85, 66, 0, 100]::numeric[])) AS v(m, s);

-- Run one semester of the seed: open, offer, register, teach, grade, approve, close.
CREATE FUNCTION pg_temp.run_seed_semester(p_term text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_sem integer;
BEGIN
    SELECT semester_id INTO v_sem FROM semesters JOIN academic_sessions USING (session_id)
    WHERE name = '2023/2024' AND term = p_term;
    UPDATE semesters SET status = 'registration_open' WHERE semester_id = v_sem;
    -- Each course is taught by the (non-head) lecturer of its department.
    INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
    SELECT c.course_id, v_sem, l.lecturer_id, 100
    FROM courses c JOIN lecturers l ON l.department_id = c.department_id AND l.staff_no LIKE '%2'
    WHERE c.code IN (SELECT DISTINCT code FROM seed_scores) AND c.term = p_term;
    INSERT INTO registrations (student_id, offering_id)
    SELECT s.student_id, o.offering_id
    FROM seed_scores x
    JOIN students s ON s.matric_no = x.matric_no
    JOIN courses c ON c.code = x.code
    JOIN course_offerings o ON o.course_id = c.course_id AND o.semester_id = v_sem;
    UPDATE semesters SET status = 'teaching' WHERE semester_id = v_sem;
    UPDATE semesters SET status = 'grading'  WHERE semester_id = v_sem;
    INSERT INTO results (registration_id, score, entered_by)
    SELECT g.registration_id, x.score, o.lecturer_id
    FROM registrations g
    JOIN course_offerings o ON o.offering_id = g.offering_id AND o.semester_id = v_sem
    JOIN students s ON s.student_id = g.student_id
    JOIN courses c ON c.course_id = o.course_id
    JOIN seed_scores x ON x.matric_no = s.matric_no AND x.code = c.code;
    UPDATE results r SET status = 'submitted'
    FROM registrations g JOIN course_offerings o USING (offering_id)
    WHERE g.registration_id = r.registration_id AND o.semester_id = v_sem;
    UPDATE results r SET status = 'approved', approved_by = d.head_lecturer_id
    FROM registrations g JOIN course_offerings o USING (offering_id)
         JOIN courses c USING (course_id) JOIN departments d USING (department_id)
    WHERE g.registration_id = r.registration_id AND o.semester_id = v_sem;
END $$;

SELECT pg_temp.run_seed_semester('first');
-- A correction before the semester closes: Zainab's PHY101 script was
-- re-marked, 30.00 -> 52.00 (F -> C), by the head of Physics.
INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
SELECT r.result_id, 52.00, 'Script re-marked: one page was not marked', d.head_lecturer_id
FROM results r JOIN registrations g USING (registration_id) JOIN students s USING (student_id)
JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id) JOIN departments d USING (department_id)
WHERE s.matric_no = 'WU/2023/0003' AND c.code = 'PHY101';
UPDATE semesters SET status = 'closed' WHERE status = 'grading';
SELECT pg_temp.run_seed_semester('second');
UPDATE semesters SET status = 'closed' WHERE status = 'grading';

COMMIT;
