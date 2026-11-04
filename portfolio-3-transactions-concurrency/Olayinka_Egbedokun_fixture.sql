-- Wavers University — Portfolio 3: data for the transaction scenarios
--
-- Run after the Portfolio 1 schema and the Portfolio 2 seed (six Computer
-- Science students with approved 2023/2024 results). Adds:
--   * 2024/2025 first semester, open for registration, with five 200-level
--     courses: CSC211, CSC213, CSC215, CSC217 (6 units each), CSC219 (3).
--     Four of the 6-unit courses make 24 units, the limit; CSC219 then
--     breaks it (scenario 2).
--   * 2025/2026 first semester, in grading, with CSC311: four students
--     each have a DRAFT score of 50.00, which the lecturer and the head of
--     department will both adjust (scenario 4).

BEGIN;

INSERT INTO courses (department_id, code, title, units, level, term)
SELECT d.department_id, v.code, v.title, v.units, v.level, 'first'
FROM (VALUES ('CSC211', 'Computer Architecture', 6, 200), ('CSC213', 'Discrete Structures', 6, 200),
             ('CSC215', 'Systems Analysis', 6, 200),      ('CSC217', 'Operating Systems I', 6, 200),
             ('CSC219', 'Technical Seminar', 3, 200),     ('CSC311', 'Database Systems', 3, 300)) AS v(code, title, units, level)
JOIN departments d ON d.code = 'CSC';

-- Offerings are taught by the CSC lecturer (WU/STF/0012), not the head.
CREATE FUNCTION pg_temp.open_semester(p_session text, p_codes text[]) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE v_sem integer;
BEGIN
    SELECT semester_id INTO v_sem FROM semesters JOIN academic_sessions USING (session_id)
    WHERE name = p_session AND term = 'first';
    UPDATE semesters SET status = 'registration_open' WHERE semester_id = v_sem;
    INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
    SELECT c.course_id, v_sem, (SELECT lecturer_id FROM lecturers WHERE staff_no = 'WU/STF/0012'), 50
    FROM courses c WHERE c.code = ANY (p_codes);
    RETURN v_sem;
END $$;

SELECT pg_temp.open_semester('2024/2025', ARRAY['CSC211', 'CSC213', 'CSC215', 'CSC217', 'CSC219']);

-- 2025/2026: register three students on CSC311, teach, start grading, and
-- enter their draft scores.
SELECT pg_temp.open_semester('2025/2026', ARRAY['CSC311']) AS s3 \gset
INSERT INTO registrations (student_id, offering_id)
SELECT s.student_id, o.offering_id
FROM students s
JOIN course_offerings o ON o.semester_id = :s3
WHERE s.matric_no IN ('WU/2023/0002', 'WU/2023/0003', 'WU/2023/0004', 'WU/2023/0006');
UPDATE semesters SET status = 'teaching' WHERE semester_id = :s3;
UPDATE semesters SET status = 'grading'  WHERE semester_id = :s3;
INSERT INTO results (registration_id, score, entered_by)
SELECT g.registration_id, 50.00, o.lecturer_id
FROM registrations g JOIN course_offerings o USING (offering_id)
WHERE o.semester_id = :s3;

COMMIT;
