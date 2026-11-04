-- Wavers University Student Result Portal — rule tests
--
-- Run on a database that has just been built from Olayinka_Egbedokun_schema.sql:
--   docker exec -i wu-postgres psql -U wavers -d <db> -X -v ON_ERROR_STOP=1 < Olayinka_Egbedokun_constraint_tests.sql
--
-- Every test judges itself. A negative test runs a statement that breaks one
-- rule and PASSES only if the database rejects it with the constraint (or
-- SQLSTATE) expected for that rule; accepted, or rejected for a different
-- reason, it FAILS. A positive control checks that valid work is accepted and
-- that derived values (grades, GPA) are exactly right.
--
-- Negative tests run inside a subtransaction that is always rolled back, so
-- they never change the data that later tests rely on. The whole file runs in
-- one transaction that is rolled back at the end: the database is left empty.

\set QUIET on
\pset footer off
BEGIN;

CREATE TEMP TABLE test_log (
    seq       serial PRIMARY KEY,
    test_id   text NOT NULL,
    rule      text NOT NULL,
    verdict   text NOT NULL,
    detail    text NOT NULL
);

-- Run p_sql (optionally as p_role); PASS if it fails with p_expect, which is
-- a constraint name or 'sqlstate:XXXXX'.
CREATE FUNCTION pg_temp.expect_error(p_id text, p_rule text, p_sql text, p_expect text, p_role text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_state text; v_con text; v_msg text; v_got text;
BEGIN
    BEGIN
        IF p_role IS NOT NULL THEN EXECUTE format('SET LOCAL ROLE %I', p_role); END IF;
        EXECUTE p_sql;
        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__accepted__';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME, v_msg = MESSAGE_TEXT;
    END;
    v_msg := regexp_replace(v_msg, 'pg_temp_[0-9]+', 'pg_temp', 'g');   -- session-specific name; keep the log reproducible
    IF v_msg = '__accepted__' THEN
        INSERT INTO pg_temp.test_log (test_id, rule, verdict, detail)
        VALUES (p_id, p_rule, 'FAIL', 'accepted, expected rejection by ' || p_expect);
        RETURN;
    END IF;
    v_got := CASE WHEN p_expect LIKE 'sqlstate:%' THEN 'sqlstate:' || v_state ELSE coalesce(nullif(v_con, ''), 'sqlstate:' || v_state) END;
    INSERT INTO pg_temp.test_log (test_id, rule, verdict, detail)
    VALUES (p_id, p_rule,
            CASE WHEN v_got = p_expect THEN 'PASS' ELSE 'FAIL' END,
            CASE WHEN v_got = p_expect THEN 'rejected by ' || v_got || ': ' || v_msg
                 ELSE 'rejected by ' || v_got || ', expected ' || p_expect || ': ' || v_msg END);
END $$;

CREATE FUNCTION pg_temp.expect_true(p_id text, p_rule text, p_ok boolean, p_what text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO pg_temp.test_log (test_id, rule, verdict, detail)
    VALUES (p_id, p_rule, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END, p_what);
$$;

-- Lookups by natural key, so tests read like the business they describe.
CREATE FUNCTION pg_temp.stu(m text) RETURNS int LANGUAGE sql AS $$ SELECT student_id FROM students WHERE matric_no = m $$;
CREATE FUNCTION pg_temp.lec(s text) RETURNS int LANGUAGE sql AS $$ SELECT lecturer_id FROM lecturers WHERE staff_no = s $$;
CREATE FUNCTION pg_temp.crs(c text) RETURNS int LANGUAGE sql AS $$ SELECT course_id FROM courses WHERE code = c $$;
CREATE FUNCTION pg_temp.sem(s text, t text) RETURNS int LANGUAGE sql AS $$
    SELECT m.semester_id FROM semesters m JOIN academic_sessions a USING (session_id) WHERE a.name = s AND m.term = t $$;
CREATE FUNCTION pg_temp.off(c text, s text, t text) RETURNS int LANGUAGE sql AS $$
    SELECT offering_id FROM course_offerings WHERE course_id = pg_temp.crs(c) AND semester_id = pg_temp.sem(s, t) $$;
CREATE FUNCTION pg_temp.reg(m text, c text, s text, t text) RETURNS int LANGUAGE sql AS $$
    SELECT registration_id FROM registrations WHERE student_id = pg_temp.stu(m) AND offering_id = pg_temp.off(c, s, t) $$;
CREATE FUNCTION pg_temp.res(m text, c text, s text, t text) RETURNS int LANGUAGE sql AS $$
    SELECT result_id FROM results WHERE registration_id = pg_temp.reg(m, c, s, t) $$;

-- The harness itself must be able to fail: an accepted statement, and a
-- rejection by a different rule than expected, must both be recorded as FAIL.
SELECT pg_temp.expect_error('H1', 'harness', $$SELECT 1$$, 'chk_never_raised');
SELECT pg_temp.expect_error('H2', 'harness', $$INSERT INTO faculties (code, name) VALUES ('bad code', 'X')$$, 'uq_faculties_code');
SELECT pg_temp.expect_true('H0', 'harness',
       (SELECT count(*) = 2 AND bool_and(verdict = 'FAIL') FROM test_log WHERE test_id IN ('H1', 'H2')),
       'the harness records an accepted statement, and a rejection by the wrong rule, as FAIL');
DELETE FROM test_log WHERE test_id IN ('H1', 'H2');

-- ===========================================================================
-- Fixture: a small, valid university (every statement here must succeed)
-- ===========================================================================

INSERT INTO faculties (code, name) VALUES ('SCI', 'Faculty of Science'), ('ART', 'Faculty of Arts');
INSERT INTO departments (faculty_id, code, name) VALUES
    ((SELECT faculty_id FROM faculties WHERE code = 'SCI'), 'CSC', 'Computer Science'),
    ((SELECT faculty_id FROM faculties WHERE code = 'SCI'), 'MTH', 'Mathematics'),
    ((SELECT faculty_id FROM faculties WHERE code = 'ART'), 'ENG', 'English');
INSERT INTO lecturers (department_id, staff_no, first_name, last_name, email)
SELECT d.department_id, v.staff_no, v.first_name, v.last_name, v.email
FROM (VALUES ('CSC', 'WU/STF/0001', 'Adaeze',  'Okafor',  'a.okafor@wavers.edu.ng'),
             ('CSC', 'WU/STF/0002', 'Bola',    'Adeyemi', 'b.adeyemi@wavers.edu.ng'),
             ('MTH', 'WU/STF/0003', 'Chidi',   'Eze',     'c.eze@wavers.edu.ng'),
             ('MTH', 'WU/STF/0004', 'Danjuma', 'Musa',    'd.musa@wavers.edu.ng'),
             ('ENG', 'WU/STF/0005', 'Efe',     'Ogun',    'e.ogun@wavers.edu.ng'),
             ('ENG', 'WU/STF/0006', 'Funke',   'Ade',     'f.ade@wavers.edu.ng'))
     AS v(dept, staff_no, first_name, last_name, email)
JOIN departments d ON d.code = v.dept;
UPDATE departments SET head_lecturer_id = pg_temp.lec('WU/STF/0001') WHERE code = 'CSC';
UPDATE departments SET head_lecturer_id = pg_temp.lec('WU/STF/0003') WHERE code = 'MTH';
UPDATE departments SET head_lecturer_id = pg_temp.lec('WU/STF/0005') WHERE code = 'ENG';
UPDATE faculties SET dean_lecturer_id = pg_temp.lec('WU/STF/0004') WHERE code = 'SCI';
UPDATE faculties SET dean_lecturer_id = pg_temp.lec('WU/STF/0006') WHERE code = 'ART';

INSERT INTO programmes (department_id, code, name, award, duration_years)
VALUES ((SELECT department_id FROM departments WHERE code = 'CSC'), 'CSC-BSC', 'Computer Science', 'B.Sc.', 4);

INSERT INTO academic_sessions (name, starts_on, ends_on) VALUES
    ('2024/2025', '2024-09-16', '2025-08-29'),
    ('2025/2026', '2025-09-15', '2026-08-28');
INSERT INTO semesters (session_id, term)
SELECT session_id, t FROM academic_sessions CROSS JOIN (VALUES ('first'), ('second')) AS v(t);

INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id, status)
SELECT v.m, v.f, v.l, v.e, (SELECT programme_id FROM programmes WHERE code = 'CSC-BSC'),
       (SELECT session_id FROM academic_sessions WHERE name = '2024/2025'), v.s
FROM (VALUES ('WU/2024/0001', 'Amaka',   'Nwosu',  'amaka.nwosu@student.wavers.edu.ng',   'active'),
             ('WU/2024/0002', 'Tunde',   'Bakare', 'tunde.bakare@student.wavers.edu.ng',  'active'),
             ('WU/2024/0003', 'Zainab',  'Bello',  'zainab.bello@student.wavers.edu.ng',  'suspended'),
             ('WU/2024/0004', 'Kelechi', 'Obi',    'kelechi.obi@student.wavers.edu.ng',   'active'),
             ('WU/2024/0005', 'Ngozi',   'Eze',    'ngozi.eze@student.wavers.edu.ng',     'active'))
     AS v(m, f, l, e, s);

INSERT INTO courses (department_id, code, title, units, level, term)
SELECT d.department_id, v.code, v.title, v.units, v.level, v.term
FROM (VALUES ('CSC', 'CSC101', 'Introduction to Computing',    3, 100, 'first'),
             ('MTH', 'MTH101', 'Elementary Mathematics I',     3, 100, 'first'),
             ('CSC', 'CSC102', 'Introduction to Programming',  3, 100, 'second'),
             ('CSC', 'CSC201', 'Data Structures',              3, 200, 'first'),
             ('CSC', 'CSC211', 'Computer Architecture',        6, 200, 'first'),
             ('CSC', 'CSC213', 'Discrete Structures',          6, 200, 'first'),
             ('CSC', 'CSC215', 'Systems Analysis',             6, 200, 'first'),
             ('CSC', 'CSC217', 'Operating Systems I',          6, 200, 'first'),
             ('CSC', 'CSC219', 'Technical Seminar',            2, 200, 'first'))
     AS v(dept, code, title, units, level, term)
JOIN departments d ON d.code = v.dept;
INSERT INTO course_prerequisites (course_id, prerequisite_id) VALUES (pg_temp.crs('CSC201'), pg_temp.crs('CSC101'));

-- 2024/2025 first semester: register, teach, grade, approve, close.
UPDATE semesters SET status = 'registration_open' WHERE semester_id = pg_temp.sem('2024/2025', 'first');
INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity) VALUES
    (pg_temp.crs('CSC101'), pg_temp.sem('2024/2025', 'first'), pg_temp.lec('WU/STF/0002'), 100),
    (pg_temp.crs('MTH101'), pg_temp.sem('2024/2025', 'first'), pg_temp.lec('WU/STF/0003'), 100);
INSERT INTO registrations (student_id, offering_id)
SELECT pg_temp.stu(m), pg_temp.off(c, '2024/2025', 'first')
FROM (VALUES ('WU/2024/0001', 'CSC101'), ('WU/2024/0001', 'MTH101'),
             ('WU/2024/0002', 'CSC101'), ('WU/2024/0002', 'MTH101'),
             ('WU/2024/0004', 'CSC101')) AS v(m, c);
UPDATE registrations SET status = 'dropped' WHERE registration_id = pg_temp.reg('WU/2024/0004', 'CSC101', '2024/2025', 'first');

SELECT pg_temp.expect_true('P01', 'R14', status = 'dropped' AND dropped_at IS NOT NULL,
       'a course can be dropped while registration is open; dropped_at is set by the database')
FROM registrations WHERE registration_id = pg_temp.reg('WU/2024/0004', 'CSC101', '2024/2025', 'first');

UPDATE semesters SET status = 'teaching' WHERE semester_id = pg_temp.sem('2024/2025', 'first');
UPDATE semesters SET status = 'grading'  WHERE semester_id = pg_temp.sem('2024/2025', 'first');

-- Scores: CSC101 entered by its lecturer (Bola); MTH101 by its lecturer, who
-- is also the head of Mathematics (Chidi), so the dean must approve those.
INSERT INTO results (registration_id, score, entered_by) VALUES
    (pg_temp.reg('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 65.00, pg_temp.lec('WU/STF/0002')),
    (pg_temp.reg('WU/2024/0002', 'CSC101', '2024/2025', 'first'), 30.00, pg_temp.lec('WU/STF/0002')),
    (pg_temp.reg('WU/2024/0001', 'MTH101', '2024/2025', 'first'), 72.50, pg_temp.lec('WU/STF/0003')),
    (pg_temp.reg('WU/2024/0002', 'MTH101', '2024/2025', 'first'), 44.99, pg_temp.lec('WU/STF/0003'));

-- Negative tests that need the semester in grading, or results still in
-- draft or submitted, are run here.
SELECT pg_temp.expect_error('T79', 'R17', $$UPDATE results SET status = 'submitted', approved_by = pg_temp.lec('WU/STF/0001')
    WHERE result_id = pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'chk_results_approved_by');
SELECT pg_temp.expect_error('T84', 'R17', $$UPDATE results SET entered_by = pg_temp.lec('WU/STF/0001')
    WHERE result_id = pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'trg_result_immutable');
SELECT pg_temp.expect_error('T43', 'R16', $$INSERT INTO results (registration_id, score, entered_by)
    VALUES (pg_temp.reg('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 101, pg_temp.lec('WU/STF/0002'))$$, 'chk_results_score');
SELECT pg_temp.expect_error('T49', 'R16', $$INSERT INTO results (registration_id, score, entered_by)
    VALUES (pg_temp.reg('WU/2024/0004', 'CSC101', '2024/2025', 'first'), 55, pg_temp.lec('WU/STF/0002'))$$, 'trg_result_registered');
SELECT pg_temp.expect_error('T50', 'R16', $$INSERT INTO results (registration_id, score, entered_by)
    VALUES (pg_temp.reg('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 80, pg_temp.lec('WU/STF/0002'))$$, 'uq_results_registration');
SELECT pg_temp.expect_error('T70', 'R16', $$INSERT INTO results (registration_id, score, entered_by)
    VALUES (pg_temp.reg('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 80, pg_temp.lec('WU/STF/0001'))$$, 'trg_result_lecturer');
SELECT pg_temp.expect_error('T71', 'R16', $$INSERT INTO results (registration_id, score, entered_by, status)
    VALUES (pg_temp.reg('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 80, pg_temp.lec('WU/STF/0002'), 'approved')$$, 'trg_result_new_draft');
SELECT pg_temp.expect_error('T45', 'R17', $$UPDATE results SET status = 'approved', approved_by = pg_temp.lec('WU/STF/0001')
    WHERE result_id = pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'trg_result_workflow');
UPDATE results SET status = 'submitted';
SELECT pg_temp.expect_true('P02', 'R17', bool_and(submitted_at IS NOT NULL AND approved_at IS NULL),
       'results move from draft to submitted; submitted_at is set by the database')
FROM results;
SELECT pg_temp.expect_error('T46', 'R17', $$UPDATE results SET status = 'approved', approved_by = pg_temp.lec('WU/STF/0001'), score = 70
    WHERE result_id = pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'trg_result_score_locked');
SELECT pg_temp.expect_error('T72', 'R17', $$UPDATE results SET score = 70
    WHERE result_id = pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'trg_result_workflow');
SELECT pg_temp.expect_error('T47', 'R17', $$UPDATE results SET status = 'approved', approved_by = pg_temp.lec('WU/STF/0003')
    WHERE result_id = pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'trg_result_approver');
SELECT pg_temp.expect_error('T48', 'R17', $$UPDATE results SET status = 'approved', approved_by = pg_temp.lec('WU/STF/0003')
    WHERE result_id = pg_temp.res('WU/2024/0001', 'MTH101', '2024/2025', 'first')$$, 'trg_result_approver');
SELECT pg_temp.expect_error('T27', 'R15', $$UPDATE semesters SET status = 'closed'
    WHERE semester_id = pg_temp.sem('2024/2025', 'first')$$, 'trg_semester_close');
SELECT pg_temp.expect_error('T53', 'R19', $$INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
    VALUES (pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 66, 'Arithmetic error in total', pg_temp.lec('WU/STF/0001'))$$,
    'trg_amendment_approved_only');

-- Return one result for correction, fix it, resubmit (positive control).
UPDATE results SET status = 'draft' WHERE result_id = pg_temp.res('WU/2024/0002', 'CSC101', '2024/2025', 'first');
UPDATE results SET score = 30.00   WHERE result_id = pg_temp.res('WU/2024/0002', 'CSC101', '2024/2025', 'first');
UPDATE results SET status = 'submitted' WHERE result_id = pg_temp.res('WU/2024/0002', 'CSC101', '2024/2025', 'first');
SELECT pg_temp.expect_true('P03', 'R17', count(*) = 4, 'a submitted result can be returned to draft, corrected and resubmitted')
FROM results WHERE status = 'submitted';

-- Approve: CSC101 by the head of Computer Science; MTH101 by the dean,
-- because the head of Mathematics marked it himself.
UPDATE results SET status = 'approved', approved_by = pg_temp.lec('WU/STF/0001')
WHERE registration_id IN (SELECT registration_id FROM registrations WHERE offering_id = pg_temp.off('CSC101', '2024/2025', 'first'));
UPDATE results SET status = 'approved', approved_by = pg_temp.lec('WU/STF/0004')
WHERE registration_id IN (SELECT registration_id FROM registrations WHERE offering_id = pg_temp.off('MTH101', '2024/2025', 'first'));
SELECT pg_temp.expect_true('P04', 'R17', count(*) = 4 AND bool_and(approved_at IS NOT NULL),
       'results approved by the head, or by the dean when the head marked the course')
FROM results WHERE status = 'approved';

-- Grades and GPA before any correction, checked against hand calculation:
--   Amaka: CSC101 65.00 = B (4) x 3 units, MTH101 72.50 = A (5) x 3 -> 27 / 6 = 4.50
--   Tunde: CSC101 30.00 = F (0) x 3,        MTH101 44.99 = E (1) x 3 ->  3 / 6 = 0.50
SELECT pg_temp.expect_true('P05', 'R20',
       (SELECT string_agg(code || '=' || grade, ',' ORDER BY student_id, code) FROM graded_courses)
         = 'CSC101=B,MTH101=A,CSC101=F,MTH101=E',
       'grades derived from scores: 65.00=B, 72.50=A, 30.00=F, 44.99=E');
SELECT pg_temp.expect_true('P06', 'R20',
       (SELECT gpa FROM semester_gpa WHERE student_id = pg_temp.stu('WU/2024/0001')) = 4.50
       AND (SELECT gpa FROM semester_gpa WHERE student_id = pg_temp.stu('WU/2024/0002')) = 0.50,
       'semester GPA matches hand calculation: 4.50 and 0.50');

-- Correction of an approved result (positive control): Tunde's MTH101 script
-- was re-marked, 44.99 -> 46.00 (E -> D). The dean is the authority here.
INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
VALUES (pg_temp.res('WU/2024/0002', 'MTH101', '2024/2025', 'first'), 46.00,
        'Script re-marked: question 4 was not added to the total', pg_temp.lec('WU/STF/0004'));
--   Tunde now: F (0) x 3 + D (2) x 3 -> 6 / 6 = 1.00; the original row is unchanged.
SELECT pg_temp.expect_true('P07', 'R19',
       (SELECT gpa FROM semester_gpa WHERE student_id = pg_temp.stu('WU/2024/0002')) = 1.00
       AND (SELECT score FROM results WHERE result_id = pg_temp.res('WU/2024/0002', 'MTH101', '2024/2025', 'first')) = 44.99
       AND (SELECT amended FROM transcript WHERE matric_no = 'WU/2024/0002' AND code = 'MTH101'),
       'an amendment changes the effective score and GPA (0.50 -> 1.00) and leaves the approved row as it was');

-- A second correction of the same result (positive control): 46.00 -> 48.00.
-- The latest correction is the one that counts, numbered revision 2.
INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
VALUES (pg_temp.res('WU/2024/0002', 'MTH101', '2024/2025', 'first'), 48.00,
        'Re-mark confirmed by external moderator', pg_temp.lec('WU/STF/0004'));
SELECT pg_temp.expect_true('P14', 'R19',
       (SELECT score FROM effective_results WHERE result_id = pg_temp.res('WU/2024/0002', 'MTH101', '2024/2025', 'first')) = 48.00
       AND (SELECT array_agg(revision ORDER BY revision) FROM result_amendments
            WHERE result_id = pg_temp.res('WU/2024/0002', 'MTH101', '2024/2025', 'first')) = '{1,2}',
       'the latest correction counts (48.00); corrections are numbered 1, 2 by the database');

UPDATE semesters SET status = 'closed' WHERE semester_id = pg_temp.sem('2024/2025', 'first');
SELECT pg_temp.expect_true('P08', 'R15', status = 'closed', 'a semester closes once every registration has an approved result')
FROM semesters WHERE semester_id = pg_temp.sem('2024/2025', 'first');

-- 2025/2026 first semester: registration open.
UPDATE semesters SET status = 'registration_open' WHERE semester_id = pg_temp.sem('2025/2026', 'first');
INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
SELECT pg_temp.crs(c), pg_temp.sem('2025/2026', 'first'), pg_temp.lec('WU/STF/0002'), cap
FROM (VALUES ('CSC101', 100), ('CSC201', 100), ('CSC211', 100), ('CSC213', 100),
             ('CSC215', 100), ('CSC217', 100), ('CSC219', 2)) AS v(c, cap);
INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
VALUES (pg_temp.crs('CSC102'), pg_temp.sem('2025/2026', 'second'), pg_temp.lec('WU/STF/0002'), 100);

INSERT INTO registrations (student_id, offering_id)
SELECT pg_temp.stu(m), pg_temp.off(c, '2025/2026', 'first')
FROM (VALUES ('WU/2024/0001', 'CSC201'), ('WU/2024/0001', 'CSC211'), ('WU/2024/0001', 'CSC213'),
             ('WU/2024/0001', 'CSC215'), ('WU/2024/0002', 'CSC101'),
             ('WU/2024/0004', 'CSC219'), ('WU/2024/0005', 'CSC219')) AS v(m, c);
SELECT pg_temp.expect_true('P09', 'R12', pg_temp.reg('WU/2024/0001', 'CSC201', '2025/2026', 'first') IS NOT NULL,
       'Amaka registers for CSC201 after passing its prerequisite CSC101');
SELECT pg_temp.expect_true('P10', 'R13', pg_temp.reg('WU/2024/0002', 'CSC101', '2025/2026', 'first') IS NOT NULL,
       'Tunde retakes CSC101, which he failed');
SELECT pg_temp.expect_true('P11', 'R11',
       (SELECT sum(c.units) FROM registrations g JOIN course_offerings o USING (offering_id) JOIN courses c USING (course_id)
        WHERE g.student_id = pg_temp.stu('WU/2024/0001') AND o.semester_id = pg_temp.sem('2025/2026', 'first')) = 21,
       'Amaka holds 21 units this semester, within the 24-unit limit');

-- ===========================================================================
-- Negative tests: each must be rejected by the named rule
-- ===========================================================================

-- R1: students
SELECT pg_temp.expect_error('T01', 'R1', $$INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
    SELECT 'WU/2024/0001', 'Copy', 'Cat', 'copy.cat@student.wavers.edu.ng', programme_id, entry_session_id FROM students WHERE matric_no = 'WU/2024/0002'$$,
    'uq_students_matric_no');
SELECT pg_temp.expect_error('T02', 'R1', $$INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
    SELECT '2024/0099', 'Bad', 'Matric', 'bad.matric@student.wavers.edu.ng', programme_id, entry_session_id FROM students WHERE matric_no = 'WU/2024/0002'$$,
    'chk_students_matric_no');
SELECT pg_temp.expect_error('T03', 'R1', $$INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
    SELECT 'WU/2024/0099', 'Same', 'Email', 'amaka.nwosu@student.wavers.edu.ng', programme_id, entry_session_id FROM students WHERE matric_no = 'WU/2024/0002'$$,
    'uq_students_email');
SELECT pg_temp.expect_error('T04', 'R1', $$INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
    SELECT 'WU/2024/0099', 'Upper', 'Case', 'Amaka.Nwosu@Student.Wavers.edu.ng', programme_id, entry_session_id FROM students WHERE matric_no = 'WU/2024/0002'$$,
    'chk_students_email');
SELECT pg_temp.expect_error('T05', 'R1', $$INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
    SELECT 'WU/2024/0099', '  ', 'Blank', 'blank@student.wavers.edu.ng', programme_id, entry_session_id FROM students WHERE matric_no = 'WU/2024/0002'$$,
    'chk_students_names');
SELECT pg_temp.expect_error('T06', 'R1', $$UPDATE students SET status = 'expelled' WHERE matric_no = 'WU/2024/0001'$$, 'chk_students_status');
SELECT pg_temp.expect_error('T07', 'R1', $$INSERT INTO students (matric_no, first_name, last_name, email, programme_id, entry_session_id)
    SELECT 'WU/2024/0099', 'No', 'Programme', 'no.programme@student.wavers.edu.ng', -1, entry_session_id FROM students WHERE matric_no = 'WU/2024/0002'$$,
    'fk_students_programme');

-- R2: lecturers
SELECT pg_temp.expect_error('T08', 'R2', $$INSERT INTO lecturers (department_id, staff_no, first_name, last_name, email)
    SELECT department_id, 'STF-0009', 'Bad', 'Staffno', 'bad.staffno@wavers.edu.ng' FROM departments WHERE code = 'CSC'$$, 'chk_lecturers_staff_no');
SELECT pg_temp.expect_error('T09', 'R2', $$INSERT INTO lecturers (department_id, staff_no, first_name, last_name, email)
    SELECT department_id, 'WU/STF/0001', 'Same', 'Staffno', 'same.staffno@wavers.edu.ng' FROM departments WHERE code = 'CSC'$$, 'uq_lecturers_staff_no');
SELECT pg_temp.expect_error('T10', 'R2', $$INSERT INTO lecturers (department_id, staff_no, first_name, last_name, email)
    SELECT department_id, 'WU/STF/0009', 'Same', 'Email', 'a.okafor@wavers.edu.ng' FROM departments WHERE code = 'CSC'$$, 'uq_lecturers_email');

SELECT pg_temp.expect_error('T87', 'R2', $$INSERT INTO lecturers (department_id, staff_no, first_name, last_name, email)
    SELECT department_id, 'WU/STF/0009', 'Upper', 'Case', 'Upper.Case@Wavers.edu.ng' FROM departments WHERE code = 'CSC'$$, 'chk_lecturers_email');

-- R3: organisation codes and names
SELECT pg_temp.expect_error('T11', 'R3', $$INSERT INTO faculties (code, name) VALUES ('sci', 'Faculty of Sciences')$$, 'chk_faculties_code');
SELECT pg_temp.expect_error('T12', 'R3', $$INSERT INTO departments (faculty_id, code, name)
    SELECT faculty_id, 'CSC', 'Computing' FROM faculties WHERE code = 'SCI'$$, 'uq_departments_code');
SELECT pg_temp.expect_error('T13', 'R3', $$INSERT INTO programmes (department_id, code, name, award, duration_years)
    SELECT department_id, 'CSC-BTECH', 'Computer Science', 'Diploma', 4 FROM departments WHERE code = 'CSC'$$, 'chk_programmes_award');

-- R4: courses
SELECT pg_temp.expect_error('T14', 'R4', $$INSERT INTO courses (department_id, code, title, units, level, term)
    SELECT department_id, 'CSC101', 'Duplicate', 3, 100, 'first' FROM departments WHERE code = 'CSC'$$, 'uq_courses_code');
SELECT pg_temp.expect_error('T15', 'R4', $$INSERT INTO courses (department_id, code, title, units, level, term)
    SELECT department_id, 'CS101', 'Bad code', 3, 100, 'first' FROM departments WHERE code = 'CSC'$$, 'chk_courses_code');
SELECT pg_temp.expect_error('T16', 'R4', $$INSERT INTO courses (department_id, code, title, units, level, term)
    SELECT department_id, 'CSC301', 'Too many units', 7, 300, 'first' FROM departments WHERE code = 'CSC'$$, 'chk_courses_units');
SELECT pg_temp.expect_error('T17', 'R4', $$INSERT INTO courses (department_id, code, title, units, level, term)
    SELECT department_id, 'CSC301', 'Wrong level', 3, 200, 'first' FROM departments WHERE code = 'CSC'$$, 'chk_courses_level');

-- R5: sessions and semesters
SELECT pg_temp.expect_error('T18', 'R5', $$INSERT INTO academic_sessions (name, starts_on, ends_on) VALUES ('2026/2028', '2026-09-14', '2027-08-27')$$,
    'chk_academic_sessions_name');
SELECT pg_temp.expect_error('T19', 'R5', $$INSERT INTO academic_sessions (name, starts_on, ends_on) VALUES ('2026/2027', '2027-08-27', '2026-09-14')$$,
    'chk_academic_sessions_dates');
SELECT pg_temp.expect_error('T20', 'R5', $$INSERT INTO semesters (session_id, term)
    SELECT session_id, 'first' FROM academic_sessions WHERE name = '2025/2026'$$, 'uq_semesters_session_term');

-- R6: prerequisites
SELECT pg_temp.expect_error('T21', 'R6', $$INSERT INTO course_prerequisites VALUES (pg_temp.crs('CSC201'), pg_temp.crs('CSC201'))$$,
    'chk_prereq_not_self');
SELECT pg_temp.expect_error('T22', 'R6', $$INSERT INTO course_prerequisites VALUES (pg_temp.crs('CSC101'), pg_temp.crs('CSC201'))$$,
    'trg_prerequisite_level');
SELECT pg_temp.expect_error('T23', 'R6', $$INSERT INTO course_prerequisites VALUES (pg_temp.crs('CSC211'), pg_temp.crs('CSC213'))$$,
    'trg_prerequisite_level');

-- R7: offerings
SELECT pg_temp.expect_error('T24', 'R7', $$INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
    VALUES (pg_temp.crs('CSC201'), pg_temp.sem('2025/2026', 'first'), pg_temp.lec('WU/STF/0002'), 50)$$, 'uq_offerings_course_semester');
SELECT pg_temp.expect_error('T25', 'R7', $$INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
    VALUES (pg_temp.crs('CSC102'), pg_temp.sem('2025/2026', 'first'), pg_temp.lec('WU/STF/0002'), 50)$$, 'trg_offering_term');
SELECT pg_temp.expect_error('T26', 'R7', $$INSERT INTO course_offerings (course_id, semester_id, lecturer_id, capacity)
    SELECT pg_temp.crs('CSC102'), semester_id, pg_temp.lec('WU/STF/0002'), 0
    FROM semesters JOIN academic_sessions USING (session_id) WHERE name = '2024/2025' AND term = 'second'$$, 'chk_offerings_capacity');
SELECT pg_temp.expect_error('T28', 'R7', $$UPDATE course_offerings SET capacity = 1
    WHERE offering_id = pg_temp.off('CSC219', '2025/2026', 'first')$$, 'trg_offering_capacity');

-- R15: semester stages
SELECT pg_temp.expect_error('T29', 'R15', $$INSERT INTO semesters (session_id, term, status)
    SELECT session_id, 'first', 'registration_open' FROM academic_sessions WHERE name = '2024/2025'$$, 'trg_semester_new_planned');
SELECT pg_temp.expect_error('T30', 'R15', $$UPDATE semesters SET status = 'teaching'
    WHERE semester_id = pg_temp.sem('2025/2026', 'second')$$, 'trg_semester_order');
SELECT pg_temp.expect_error('T31', 'R15', $$UPDATE semesters SET status = 'planned'
    WHERE semester_id = pg_temp.sem('2025/2026', 'first')$$, 'trg_semester_order');

-- R8–R13: registration
SELECT pg_temp.expect_error('T32', 'R8', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0001'), pg_temp.off('CSC102', '2025/2026', 'second'))$$, 'trg_registration_window');
SELECT pg_temp.expect_error('T33', 'R9', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0003'), pg_temp.off('CSC101', '2025/2026', 'first'))$$, 'trg_registration_student_active');
SELECT pg_temp.expect_error('T34', 'R10', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0001'), pg_temp.off('CSC219', '2025/2026', 'first'))$$, 'trg_registration_capacity');
SELECT pg_temp.expect_error('T35', 'R11', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0001'), pg_temp.off('CSC217', '2025/2026', 'first'))$$, 'trg_registration_unit_limit');
SELECT pg_temp.expect_error('T36', 'R12', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0002'), pg_temp.off('CSC201', '2025/2026', 'first'))$$, 'trg_registration_prerequisite');
SELECT pg_temp.expect_error('T37', 'R13', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0001'), pg_temp.off('CSC101', '2025/2026', 'first'))$$, 'trg_registration_already_passed');
SELECT pg_temp.expect_error('T38', 'R13', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0002'), pg_temp.off('CSC101', '2025/2026', 'first'))$$, 'uq_registrations_student_offering');
SELECT pg_temp.expect_error('T39', 'R13', $$INSERT INTO registrations (student_id, offering_id, status)
    VALUES (pg_temp.stu('WU/2024/0005'), pg_temp.off('CSC201', '2025/2026', 'first'), 'dropped')$$, 'trg_registration_new');

-- R14: changing a registration
SELECT pg_temp.expect_error('T40', 'R14', $$UPDATE registrations SET status = 'registered'
    WHERE registration_id = pg_temp.reg('WU/2024/0004', 'CSC101', '2024/2025', 'first')$$, 'trg_registration_drop_final');
SELECT pg_temp.expect_error('T41', 'R14', $$UPDATE registrations SET status = 'dropped'
    WHERE registration_id = pg_temp.reg('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'trg_registration_drop_window');
SELECT pg_temp.expect_error('T42', 'R14', $$UPDATE registrations SET offering_id = pg_temp.off('CSC211', '2025/2026', 'first')
    WHERE registration_id = pg_temp.reg('WU/2024/0004', 'CSC219', '2025/2026', 'first')$$, 'trg_registration_immutable');

-- R16: entering results
SELECT pg_temp.expect_error('T44', 'R16', $$INSERT INTO results (registration_id, score, entered_by)
    VALUES (pg_temp.reg('WU/2024/0004', 'CSC219', '2025/2026', 'first'), 55, pg_temp.lec('WU/STF/0002'))$$, 'trg_result_window');

-- R17: approved results are final
SELECT pg_temp.expect_error('T51', 'R17', $$UPDATE results SET score = 99
    WHERE result_id = pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first')$$, 'trg_result_final');

-- R18: heads and deans
SELECT pg_temp.expect_error('T52', 'R18', $$UPDATE departments SET head_lecturer_id = pg_temp.lec('WU/STF/0002') WHERE code = 'ENG'$$,
    'fk_departments_head');
SELECT pg_temp.expect_error('T54', 'R18', $$UPDATE faculties SET dean_lecturer_id = pg_temp.lec('WU/STF/0006') WHERE code = 'SCI'$$,
    'trg_faculty_dean');

-- R19: amendments
SELECT pg_temp.expect_error('T55', 'R19', $$INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
    VALUES (pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 66, 'Arithmetic error in total', pg_temp.lec('WU/STF/0002'))$$,
    'trg_amendment_by_head');
SELECT pg_temp.expect_error('T56', 'R19', $$INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
    VALUES (pg_temp.res('WU/2024/0002', 'MTH101', '2024/2025', 'first'), 48.00, 'Third re-mark, no change', pg_temp.lec('WU/STF/0004'))$$,
    'trg_amendment_changes_score');
SELECT pg_temp.expect_error('T57', 'R19', $$INSERT INTO result_amendments (result_id, new_score, reason, amended_by)
    VALUES (pg_temp.res('WU/2024/0001', 'CSC101', '2024/2025', 'first'), 66, 'typo', pg_temp.lec('WU/STF/0001'))$$,
    'chk_amendments_reason');
SELECT pg_temp.expect_error('T58', 'R19', $$UPDATE result_amendments SET new_score = 90$$, 'trg_records_permanent');

-- R20: the grading scale
SELECT pg_temp.expect_error('T59', 'R20', $$UPDATE grade_scale SET max_score = 72.00 WHERE grade = 'B'$$,
    'ex_grade_scale_no_overlap');
SELECT pg_temp.expect_true('P12', 'R20',
       (SELECT count(*) = 10001 AND bool_and(n = 1)
        FROM (SELECT s, count(g.grade) AS n
              FROM generate_series(0, 10000) AS i(i)
              CROSS JOIN LATERAL (SELECT (i / 100.0)::numeric(5,2) AS s) x
              LEFT JOIN grade_scale g ON x.s <@ g.score_range
              GROUP BY s) per_score),
       'every score from 0.00 to 100.00 maps to exactly one grade (10,001 scores, no gaps, no overlaps)');

-- R21: records are permanent
SELECT pg_temp.expect_error('T60', 'R21', $$DELETE FROM results$$, 'trg_records_permanent');
SELECT pg_temp.expect_error('T61', 'R21', $$DELETE FROM registrations$$, 'trg_records_permanent');
SELECT pg_temp.expect_error('T62', 'R21', $$TRUNCATE results CASCADE$$, 'trg_records_permanent');
SELECT pg_temp.expect_error('T63', 'R21', $$DELETE FROM result_amendments$$, 'trg_records_permanent');
SELECT pg_temp.expect_error('T88', 'R21', $$TRUNCATE registrations CASCADE$$, 'trg_records_permanent');
SELECT pg_temp.expect_error('T89', 'R21', $$TRUNCATE result_amendments$$, 'trg_records_permanent');

-- R3: programmes
SELECT pg_temp.expect_error('T74', 'R3', $$INSERT INTO programmes (department_id, code, name, award, duration_years)
    SELECT department_id, 'any thing!', 'Software Engineering', 'B.Sc.', 4 FROM departments WHERE code = 'CSC'$$, 'chk_programmes_code');
SELECT pg_temp.expect_error('T75', 'R3', $$INSERT INTO programmes (department_id, code, name, award, duration_years)
    SELECT department_id, 'CSC-CS', 'Computer Science', 'B.Sc.', 4 FROM departments WHERE code = 'CSC'$$, 'uq_programmes_name_award');

-- R18: one post per person, and a dean is never a head
SELECT pg_temp.expect_error('T76', 'R18', $$UPDATE faculties SET dean_lecturer_id = pg_temp.lec('WU/STF/0001') WHERE code = 'SCI'$$,
    'trg_dean_not_head');
SELECT pg_temp.expect_error('T77', 'R18', $$UPDATE departments SET head_lecturer_id = pg_temp.lec('WU/STF/0004') WHERE code = 'MTH'$$,
    'trg_dean_not_head');
SELECT pg_temp.expect_error('T78', 'R18', $$UPDATE departments SET head_lecturer_id = pg_temp.lec('WU/STF/0001') WHERE code = 'MTH'$$,
    'uq_departments_head');

-- R7 / R15: an offering's course and a semester's term never change
SELECT pg_temp.expect_error('T85', 'R7', $$UPDATE course_offerings SET course_id = pg_temp.crs('CSC213')
    WHERE offering_id = pg_temp.off('CSC211', '2025/2026', 'first')$$, 'trg_offering_immutable');
SELECT pg_temp.expect_error('T86', 'R15', $$UPDATE semesters SET term = 'second'
    WHERE semester_id = pg_temp.sem('2025/2026', 'first')$$, 'trg_semester_immutable');

-- R22: a session's own temporary table cannot stand in for a real one. The
-- (superuser) test session shadows course_prerequisites with an empty
-- temporary table; the prerequisite rule must still see the real table.
CREATE TEMP TABLE course_prerequisites (course_id integer, prerequisite_id integer);
SELECT pg_temp.expect_error('T81', 'R22', $$INSERT INTO registrations (student_id, offering_id)
    VALUES (pg_temp.stu('WU/2024/0002'), pg_temp.off('CSC201', '2025/2026', 'first'))$$, 'trg_registration_prerequisite');
DROP TABLE pg_temp.course_prerequisites;

-- R22: the application role cannot bypass the rules
SELECT pg_temp.expect_error('T64', 'R22', $$DELETE FROM students WHERE matric_no = 'WU/2024/0005'$$, 'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T65', 'R22', $$UPDATE results SET entered_by = 1$$, 'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T66', 'R22', $$ALTER TABLE results DISABLE TRIGGER trg_result_guard$$, 'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T67', 'R22', $$SET session_replication_role = replica$$, 'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T68', 'R22', $$UPDATE grade_scale SET points = 5$$, 'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T69', 'R22', $$UPDATE registrations SET dropped_at = now()$$, 'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T80', 'R22', $$CREATE TEMP TABLE course_prerequisites (course_id integer, prerequisite_id integer)$$,
    'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T82', 'R22', $$INSERT INTO faculties (faculty_id, code, name) OVERRIDING SYSTEM VALUE VALUES (999, 'XYZ', 'Faculty of X')$$,
    'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_error('T83', 'R22', $$INSERT INTO registrations (student_id, offering_id, status)
    VALUES (1, 1, 'registered')$$, 'sqlstate:42501', 'portal_app');
SELECT pg_temp.expect_true('P15', 'R22',
       NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
                   WHERE grantee = 'portal_app' AND privilege_type IN ('DELETE', 'TRUNCATE', 'TRIGGER', 'REFERENCES'))
       AND NOT EXISTS (SELECT 1 FROM pg_class WHERE relowner = 'portal_app'::regrole)
       AND NOT has_database_privilege('portal_app', current_database(), 'TEMPORARY'),
       'portal_app has no DELETE, TRUNCATE, TRIGGER or REFERENCES grant, owns nothing, and cannot create temporary tables');

-- Positive control: the application role can run the whole workflow, from
-- registration to approval, with only the privileges it was granted.
-- (Identifiers are looked up first: the role uses plain SQL, no helpers.)
SELECT pg_temp.stu('WU/2024/0005') AS ngozi, pg_temp.off('CSC211', '2025/2026', 'first') AS csc211,
       pg_temp.sem('2025/2026', 'first') AS s2, pg_temp.lec('WU/STF/0002') AS bola, pg_temp.lec('WU/STF/0001') AS adaeze \gset
SET LOCAL ROLE portal_app;
INSERT INTO registrations (student_id, offering_id) VALUES (:ngozi, :csc211);
UPDATE semesters SET status = 'teaching' WHERE semester_id = :s2;
RESET ROLE;
SELECT pg_temp.expect_error('T73', 'R14', $$UPDATE registrations SET status = 'dropped'
    WHERE registration_id = pg_temp.reg('WU/2024/0004', 'CSC219', '2025/2026', 'first')$$, 'trg_registration_drop_window');
SET LOCAL ROLE portal_app;
UPDATE semesters SET status = 'grading'  WHERE semester_id = :s2;
INSERT INTO results (registration_id, score, entered_by)
SELECT registration_id, 58.50, :bola FROM registrations WHERE student_id = :ngozi AND offering_id = :csc211;
UPDATE results SET status = 'submitted'
WHERE registration_id = (SELECT registration_id FROM registrations WHERE student_id = :ngozi AND offering_id = :csc211);
UPDATE results SET status = 'approved', approved_by = :adaeze
WHERE registration_id = (SELECT registration_id FROM registrations WHERE student_id = :ngozi AND offering_id = :csc211);
RESET ROLE;
SELECT pg_temp.expect_true('P13', 'R22',
       (SELECT grade FROM transcript WHERE matric_no = 'WU/2024/0005' AND code = 'CSC211') = 'C',
       'portal_app registers, enters, submits and approves a result (58.50 = C) with only its grants');

\echo
\echo '=== Test log ==='
SELECT test_id, rule, verdict, detail FROM test_log ORDER BY test_id;

\echo
\echo '=== Summary ==='
SELECT count(*) FILTER (WHERE verdict = 'PASS') AS passed,
       count(*) FILTER (WHERE verdict = 'FAIL') AS failed,
       count(*)                                 AS total
FROM test_log;
SELECT 'RESULT: ' || count(*) FILTER (WHERE verdict = 'PASS') || ' PASS, '
                  || count(*) FILTER (WHERE verdict = 'FAIL') || ' FAIL' AS result
FROM test_log \gset
\echo :result

ROLLBACK;
