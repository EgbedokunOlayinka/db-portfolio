-- Wavers University — Portfolio 1: data for the concurrency check
--
-- Three courses with ONE place each, in a semester open for registration,
-- and two students who will race for each place (see the reproduce script).

INSERT INTO faculties (code, name) VALUES ('SCI', 'Faculty of Science');
INSERT INTO departments (faculty_id, code, name)
SELECT faculty_id, 'CSC', 'Computer Science' FROM faculties WHERE code = 'SCI';
INSERT INTO lecturers (department_id, staff_no, first_name, last_name, email)
SELECT department_id, 'WU/STF/0002', 'Bola', 'Adeyemi', 'b.adeyemi@wavers.edu.ng' FROM departments WHERE code = 'CSC';
INSERT INTO programmes (department_id, code, name, award, duration_years)
SELECT department_id, 'CSC-BSC', 'Computer Science', 'B.Sc.', 4 FROM departments WHERE code = 'CSC';
INSERT INTO academic_sessions (name, starts_on, ends_on) VALUES ('2025/2026', '2025-09-15', '2026-08-28');
INSERT INTO semesters (session_id, term) SELECT session_id, 'first' FROM academic_sessions;
UPDATE semesters SET status = 'registration_open';

INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
SELECT v.m, v.f, v.l, v.e, p.programme_id, a.session_id
FROM (VALUES ('WU/2025/0001', 'Ada',   'Obi',   'ada.obi@student.wavers.edu.ng'),
             ('WU/2025/0002', 'Bayo',  'Ojo',   'bayo.ojo@student.wavers.edu.ng')) AS v(m, f, l, e)
CROSS JOIN programmes p CROSS JOIN academic_sessions a;

INSERT INTO courses (department_id, code, title, units, level, term)
SELECT d.department_id, v.code, v.title, 2, 300, 'first'
FROM (VALUES ('CSC301', 'Seminar A'), ('CSC303', 'Seminar B'), ('CSC305', 'Seminar C')) AS v(code, title)
CROSS JOIN departments d;
INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
SELECT c.course_id, s.semester_id, l.lecturer_id, 1
FROM courses c CROSS JOIN semesters s CROSS JOIN lecturers l;
