-- Wavers University Student Result Portal — relational schema (PostgreSQL 18)
--
-- Run on an empty database:
--   docker exec -i wu-postgres psql -U wavers -d <db> -X -v ON_ERROR_STOP=1 < Olayinka_Egbedokun_schema.sql
--
-- The whole schema is created in one transaction, so a failure leaves nothing
-- half-built. Business rules are numbered R1–R22; each is listed with its
-- enforcement in Olayinka_Egbedokun_database_design.md, and each enforced rule
-- has a negative test in Olayinka_Egbedokun_constraint_tests.sql.
--
-- Conventions: surrogate identity keys (GENERATED ALWAYS; the application
-- role has no INSERT privilege on them, so only the database assigns them),
-- natural keys kept UNIQUE, every constraint named (pk_, fk_, uq_, chk_, ex_,
-- and trg_ for rules raised by triggers) so a rejection says which rule fired.
-- Every function pins its search_path, so no session can substitute its own
-- tables (for example a temporary table) for the ones a rule reads.

BEGIN;

-- ---------------------------------------------------------------------------
-- Organisation: faculties, departments, programmes, lecturers
-- ---------------------------------------------------------------------------

CREATE TABLE faculties (
    faculty_id  integer GENERATED ALWAYS AS IDENTITY,
    code             text NOT NULL,
    name             text NOT NULL,
    dean_lecturer_id integer,              -- set once the dean exists (FK added below)
    CONSTRAINT pk_faculties PRIMARY KEY (faculty_id),
    CONSTRAINT uq_faculties_code UNIQUE (code),
    CONSTRAINT uq_faculties_name UNIQUE (name),
    CONSTRAINT chk_faculties_code CHECK (code ~ '^[A-Z]{2,6}$'),
    CONSTRAINT chk_faculties_name CHECK (btrim(name) <> '')
);

CREATE TABLE departments (
    department_id     integer GENERATED ALWAYS AS IDENTITY,
    faculty_id        integer NOT NULL,
    code              text NOT NULL,
    name              text NOT NULL,
    head_lecturer_id  integer,              -- set once the head exists (FK added below)
    CONSTRAINT pk_departments PRIMARY KEY (department_id),
    CONSTRAINT fk_departments_faculty FOREIGN KEY (faculty_id) REFERENCES faculties,
    CONSTRAINT uq_departments_code UNIQUE (code),
    CONSTRAINT uq_departments_name UNIQUE (name),
    CONSTRAINT chk_departments_code CHECK (code ~ '^[A-Z]{3}$'),
    CONSTRAINT chk_departments_name CHECK (btrim(name) <> '')
);

CREATE TABLE programmes (
    programme_id    integer GENERATED ALWAYS AS IDENTITY,
    department_id   integer NOT NULL,
    code            text NOT NULL,
    name            text NOT NULL,
    award           text NOT NULL,
    duration_years  smallint NOT NULL,
    CONSTRAINT pk_programmes PRIMARY KEY (programme_id),
    CONSTRAINT fk_programmes_department FOREIGN KEY (department_id) REFERENCES departments,
    CONSTRAINT uq_programmes_code UNIQUE (code),
    CONSTRAINT uq_programmes_name_award UNIQUE (name, award),
    CONSTRAINT chk_programmes_code CHECK (code ~ '^[A-Z]{3}-[A-Z]{2,5}$'),
    CONSTRAINT chk_programmes_name CHECK (btrim(name) <> ''),
    CONSTRAINT chk_programmes_award CHECK (award IN ('B.Sc.', 'B.Eng.', 'B.A.', 'B.Tech.')),
    CONSTRAINT chk_programmes_duration CHECK (duration_years BETWEEN 4 AND 6)
);

CREATE TABLE lecturers (
    lecturer_id    integer GENERATED ALWAYS AS IDENTITY,
    department_id  integer NOT NULL,
    staff_no       text NOT NULL,
    first_name     text NOT NULL,
    last_name      text NOT NULL,
    email          text NOT NULL,
    CONSTRAINT pk_lecturers PRIMARY KEY (lecturer_id),
    CONSTRAINT fk_lecturers_department FOREIGN KEY (department_id) REFERENCES departments,
    CONSTRAINT uq_lecturers_staff_no UNIQUE (staff_no),
    CONSTRAINT chk_lecturers_staff_no CHECK (staff_no ~ '^WU/STF/[0-9]{4}$'),
    CONSTRAINT chk_lecturers_names CHECK (btrim(first_name) <> '' AND btrim(last_name) <> ''),
    CONSTRAINT chk_lecturers_email CHECK (email = lower(btrim(email)) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
CREATE UNIQUE INDEX uq_lecturers_email ON lecturers (email);

-- A department's head is one of its own lecturers (R18). The composite FK
-- makes that structural: (head, department) must exist as a lecturer row.
ALTER TABLE lecturers ADD CONSTRAINT uq_lecturers_id_department UNIQUE (lecturer_id, department_id);
ALTER TABLE departments ADD CONSTRAINT fk_departments_head
    FOREIGN KEY (head_lecturer_id, department_id) REFERENCES lecturers (lecturer_id, department_id);
ALTER TABLE faculties ADD CONSTRAINT fk_faculties_dean
    FOREIGN KEY (dean_lecturer_id) REFERENCES lecturers;
-- One post per person: a lecturer heads at most one department and is dean
-- of at most one faculty (R18). NULLs (vacant posts) do not collide.
ALTER TABLE departments ADD CONSTRAINT uq_departments_head UNIQUE (head_lecturer_id);
ALTER TABLE faculties ADD CONSTRAINT uq_faculties_dean UNIQUE (dean_lecturer_id);

-- ---------------------------------------------------------------------------
-- Academic calendar: sessions and semesters
-- ---------------------------------------------------------------------------

CREATE TABLE academic_sessions (
    session_id  integer GENERATED ALWAYS AS IDENTITY,
    name        text NOT NULL,                  -- e.g. 2025/2026
    starts_on   date NOT NULL,
    ends_on     date NOT NULL,
    CONSTRAINT pk_academic_sessions PRIMARY KEY (session_id),
    CONSTRAINT uq_academic_sessions_name UNIQUE (name),
    CONSTRAINT chk_academic_sessions_name CHECK (
        name ~ '^[0-9]{4}/[0-9]{4}$'
        AND split_part(name, '/', 2)::int = split_part(name, '/', 1)::int + 1),
    CONSTRAINT chk_academic_sessions_dates CHECK (ends_on > starts_on)
);

-- A semester moves through its stages in order and never back (R15):
-- planned -> registration_open -> teaching -> grading -> closed
CREATE TABLE semesters (
    semester_id  integer GENERATED ALWAYS AS IDENTITY,
    session_id   integer NOT NULL,
    term         text NOT NULL,
    status       text NOT NULL DEFAULT 'planned',
    CONSTRAINT pk_semesters PRIMARY KEY (semester_id),
    CONSTRAINT fk_semesters_session FOREIGN KEY (session_id) REFERENCES academic_sessions,
    CONSTRAINT uq_semesters_session_term UNIQUE (session_id, term),
    CONSTRAINT chk_semesters_term CHECK (term IN ('first', 'second')),
    CONSTRAINT chk_semesters_status CHECK (status IN ('planned', 'registration_open', 'teaching', 'grading', 'closed'))
);

-- ---------------------------------------------------------------------------
-- People studying: students
-- ---------------------------------------------------------------------------

CREATE TABLE students (
    student_id        integer GENERATED ALWAYS AS IDENTITY,
    matric_no         text NOT NULL,
    first_name        text NOT NULL,
    last_name         text NOT NULL,
    email             text NOT NULL,
    programme_id      integer NOT NULL,
    entry_session_id  integer NOT NULL,
    status            text NOT NULL DEFAULT 'active',
    CONSTRAINT pk_students PRIMARY KEY (student_id),
    CONSTRAINT fk_students_programme FOREIGN KEY (programme_id) REFERENCES programmes,
    CONSTRAINT fk_students_entry_session FOREIGN KEY (entry_session_id) REFERENCES academic_sessions,
    CONSTRAINT uq_students_matric_no UNIQUE (matric_no),
    CONSTRAINT chk_students_matric_no CHECK (matric_no ~ '^WU/[0-9]{4}/[0-9]{4}$'),
    CONSTRAINT chk_students_names CHECK (btrim(first_name) <> '' AND btrim(last_name) <> ''),
    CONSTRAINT chk_students_email CHECK (email = lower(btrim(email)) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT chk_students_status CHECK (status IN ('active', 'suspended', 'withdrawn', 'graduated'))
);
CREATE UNIQUE INDEX uq_students_email ON students (email);

-- ---------------------------------------------------------------------------
-- Curriculum: courses, prerequisites, offerings
-- ---------------------------------------------------------------------------

CREATE TABLE courses (
    course_id      integer GENERATED ALWAYS AS IDENTITY,
    department_id  integer NOT NULL,
    code           text NOT NULL,               -- e.g. CSC201: 3 letters, level digit, 2 digits
    title          text NOT NULL,
    units          smallint NOT NULL,
    level          smallint NOT NULL,
    term           text NOT NULL,               -- the semester the course is taught in
    CONSTRAINT pk_courses PRIMARY KEY (course_id),
    CONSTRAINT fk_courses_department FOREIGN KEY (department_id) REFERENCES departments,
    CONSTRAINT uq_courses_code UNIQUE (code),
    CONSTRAINT chk_courses_code CHECK (code ~ '^[A-Z]{3}[1-5][0-9]{2}$'),
    CONSTRAINT chk_courses_title CHECK (btrim(title) <> ''),
    CONSTRAINT chk_courses_units CHECK (units BETWEEN 1 AND 6),
    CONSTRAINT chk_courses_level CHECK (level = substr(code, 4, 1)::int * 100),
    CONSTRAINT chk_courses_term CHECK (term IN ('first', 'second'))
);

CREATE TABLE course_prerequisites (
    course_id        integer NOT NULL,
    prerequisite_id  integer NOT NULL,
    CONSTRAINT pk_course_prerequisites PRIMARY KEY (course_id, prerequisite_id),
    CONSTRAINT fk_prereq_course FOREIGN KEY (course_id) REFERENCES courses,
    CONSTRAINT fk_prereq_prerequisite FOREIGN KEY (prerequisite_id) REFERENCES courses,
    CONSTRAINT chk_prereq_not_self CHECK (course_id <> prerequisite_id)
);

CREATE TABLE course_offerings (
    offering_id  integer GENERATED ALWAYS AS IDENTITY,
    course_id    integer NOT NULL,
    semester_id  integer NOT NULL,
    lecturer_id  integer NOT NULL,              -- the lecturer who enters the scores
    capacity     integer NOT NULL,
    CONSTRAINT pk_course_offerings PRIMARY KEY (offering_id),
    CONSTRAINT fk_offerings_course FOREIGN KEY (course_id) REFERENCES courses,
    CONSTRAINT fk_offerings_semester FOREIGN KEY (semester_id) REFERENCES semesters,
    CONSTRAINT fk_offerings_lecturer FOREIGN KEY (lecturer_id) REFERENCES lecturers,
    CONSTRAINT uq_offerings_course_semester UNIQUE (course_id, semester_id),
    CONSTRAINT chk_offerings_capacity CHECK (capacity > 0)
);

-- ---------------------------------------------------------------------------
-- Registration and results
-- ---------------------------------------------------------------------------

CREATE TABLE registrations (
    registration_id  integer GENERATED ALWAYS AS IDENTITY,
    student_id       integer NOT NULL,
    offering_id      integer NOT NULL,
    status           text NOT NULL DEFAULT 'registered',
    registered_at    timestamptz NOT NULL DEFAULT now(),
    dropped_at       timestamptz,
    CONSTRAINT pk_registrations PRIMARY KEY (registration_id),
    CONSTRAINT fk_registrations_student FOREIGN KEY (student_id) REFERENCES students,
    CONSTRAINT fk_registrations_offering FOREIGN KEY (offering_id) REFERENCES course_offerings,
    CONSTRAINT uq_registrations_student_offering UNIQUE (student_id, offering_id),
    CONSTRAINT chk_registrations_status CHECK (status IN ('registered', 'dropped')),
    CONSTRAINT chk_registrations_dropped CHECK ((status = 'dropped') = (dropped_at IS NOT NULL))
);

-- The grading scale: the Nigerian five-point scale. Each grade covers a
-- closed range of scores; the exclusion constraint forbids two grades whose
-- ranges overlap (R20), so every score maps to at most one grade.
CREATE TABLE grade_scale (
    grade       char(1) NOT NULL,
    min_score   numeric(5,2) NOT NULL,
    max_score   numeric(5,2) NOT NULL,
    points      smallint NOT NULL,
    score_range numrange GENERATED ALWAYS AS (numrange(min_score, max_score, '[]')) STORED,
    CONSTRAINT pk_grade_scale PRIMARY KEY (grade),
    CONSTRAINT uq_grade_scale_points UNIQUE (points),
    CONSTRAINT chk_grade_scale_bounds CHECK (0 <= min_score AND min_score <= max_score AND max_score <= 100),
    CONSTRAINT chk_grade_scale_points CHECK (points BETWEEN 0 AND 5),
    CONSTRAINT ex_grade_scale_no_overlap EXCLUDE USING gist (score_range WITH &&)
);

-- One result per registration. A lecturer enters it as a draft, submits it,
-- and the head of the course's department approves it (R16, R17). The grade
-- is not stored: it is derived from the score through grade_scale.
CREATE TABLE results (
    result_id        integer GENERATED ALWAYS AS IDENTITY,
    registration_id  integer NOT NULL,
    score            numeric(5,2) NOT NULL,
    status           text NOT NULL DEFAULT 'draft',
    entered_by       integer NOT NULL,
    entered_at       timestamptz NOT NULL DEFAULT now(),
    submitted_at     timestamptz,
    approved_by      integer,
    approved_at      timestamptz,
    CONSTRAINT pk_results PRIMARY KEY (result_id),
    CONSTRAINT fk_results_registration FOREIGN KEY (registration_id) REFERENCES registrations,
    CONSTRAINT fk_results_entered_by FOREIGN KEY (entered_by) REFERENCES lecturers,
    CONSTRAINT fk_results_approved_by FOREIGN KEY (approved_by) REFERENCES lecturers,
    CONSTRAINT uq_results_registration UNIQUE (registration_id),
    CONSTRAINT chk_results_score CHECK (score BETWEEN 0 AND 100),
    CONSTRAINT chk_results_status CHECK (status IN ('draft', 'submitted', 'approved')),
    CONSTRAINT chk_results_submitted CHECK ((status <> 'draft') = (submitted_at IS NOT NULL)),
    CONSTRAINT chk_results_approved_by CHECK ((status = 'approved') = (approved_by IS NOT NULL)),
    CONSTRAINT chk_results_approved_at CHECK ((status = 'approved') = (approved_at IS NOT NULL)),
    CONSTRAINT chk_results_four_eyes CHECK (approved_by <> entered_by)
);

-- An approved result is never edited. A correction is a new, append-only
-- amendment row; the effective score is the one with the highest revision
-- (R19). The revision is numbered by the trigger while it holds a lock on
-- the result, so it follows the order in which corrections were made.
CREATE TABLE result_amendments (
    amendment_id  integer GENERATED ALWAYS AS IDENTITY,
    result_id     integer NOT NULL,
    new_score     numeric(5,2) NOT NULL,
    reason        text NOT NULL,
    amended_by    integer NOT NULL,
    amended_at    timestamptz NOT NULL DEFAULT now(),
    revision      smallint NOT NULL,          -- 1, 2, 3... per result, set by the trigger
    CONSTRAINT pk_result_amendments PRIMARY KEY (amendment_id),
    CONSTRAINT uq_amendments_result_revision UNIQUE (result_id, revision),
    CONSTRAINT fk_amendments_result FOREIGN KEY (result_id) REFERENCES results,
    CONSTRAINT fk_amendments_amended_by FOREIGN KEY (amended_by) REFERENCES lecturers,
    CONSTRAINT chk_amendments_score CHECK (new_score BETWEEN 0 AND 100),
    CONSTRAINT chk_amendments_reason CHECK (length(btrim(reason)) >= 10)
);

-- Foreign keys are not indexed automatically. These serve the lookups the
-- triggers and views below make on every write and read.
CREATE INDEX ix_departments_faculty ON departments (faculty_id);
CREATE INDEX ix_programmes_department ON programmes (department_id);
CREATE INDEX ix_lecturers_department ON lecturers (department_id);
CREATE INDEX ix_students_programme ON students (programme_id);
CREATE INDEX ix_courses_department ON courses (department_id);
CREATE INDEX ix_prereq_prerequisite ON course_prerequisites (prerequisite_id);
CREATE INDEX ix_offerings_semester ON course_offerings (semester_id);
CREATE INDEX ix_offerings_lecturer ON course_offerings (lecturer_id);
CREATE INDEX ix_registrations_offering ON registrations (offering_id);

-- ---------------------------------------------------------------------------
-- Derived data: effective scores, grades, GPA, transcript (R20: never stored)
-- ---------------------------------------------------------------------------

-- Approved results with the score that counts: the latest amendment's, if any.
CREATE VIEW effective_results AS
SELECT r.result_id,
       r.registration_id,
       g.student_id,
       g.offering_id,
       coalesce(a.new_score, r.score) AS score,
       a.amendment_id IS NOT NULL     AS amended
FROM results r
JOIN registrations g ON g.registration_id = r.registration_id
LEFT JOIN LATERAL (
    SELECT ra.amendment_id, ra.new_score
    FROM result_amendments ra
    WHERE ra.result_id = r.result_id
    ORDER BY ra.revision DESC
    LIMIT 1
) a ON true
WHERE r.status = 'approved';

-- Every counted course with its grade, points and term.
CREATE VIEW graded_courses AS
SELECT e.student_id,
       o.semester_id,
       c.course_id,
       c.code,
       c.title,
       c.units,
       e.score,
       gs.grade,
       gs.points,
       e.amended
FROM effective_results e
JOIN course_offerings o ON o.offering_id = e.offering_id
JOIN courses c          ON c.course_id = o.course_id
JOIN grade_scale gs     ON e.score <@ gs.score_range;

-- GPA for one semester: total (grade points x units) / total units.
CREATE VIEW semester_gpa AS
SELECT student_id,
       semester_id,
       sum(units)                                              AS units_taken,
       coalesce(sum(units) FILTER (WHERE points > 0), 0)      AS units_passed,
       round(sum(points * units)::numeric / sum(units), 2)     AS gpa
FROM graded_courses
GROUP BY student_id, semester_id;

-- CGPA across every semester so far. Every attempt counts, including a
-- failed attempt of a course later passed: both stay on the record.
CREATE VIEW student_cgpa AS
SELECT student_id,
       sum(units)                                              AS units_taken,
       coalesce(sum(units) FILTER (WHERE points > 0), 0)      AS units_passed,
       round(sum(points * units)::numeric / sum(units), 2)     AS cgpa
FROM graded_courses
GROUP BY student_id;

-- The transcript: one line per counted course. Readers order it by
-- starts_on, term and code (a view has no order of its own).
CREATE VIEW transcript AS
SELECT s.matric_no,
       s.last_name || ', ' || s.first_name AS student_name,
       ac.name  AS session,
       sm.term,
       gc.code,
       gc.title,
       gc.units,
       gc.score,
       gc.grade,
       gc.points,
       gc.amended,
       ac.starts_on,
       sm.semester_id
FROM graded_courses gc
JOIN students s           ON s.student_id = gc.student_id
JOIN semesters sm         ON sm.semester_id = gc.semester_id
JOIN academic_sessions ac ON ac.session_id = sm.session_id;

-- Has the student passed this course? (any counted attempt with points > 0)
-- The pass mark is not hard-coded: it is whatever the grade scale says.
CREATE FUNCTION has_passed(p_student integer, p_course integer)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (
        SELECT 1 FROM graded_courses
        WHERE student_id = p_student AND course_id = p_course AND points > 0)
$$;

-- ---------------------------------------------------------------------------
-- Rule triggers
-- ---------------------------------------------------------------------------

-- R18: a faculty's dean is a lecturer in one of the faculty's departments.
CREATE FUNCTION faculty_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    IF NEW.dean_lecturer_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM departments WHERE head_lecturer_id = NEW.dean_lecturer_id) THEN
        RAISE EXCEPTION 'a head of department cannot also be a dean'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_dean_not_head';
    END IF;
    IF NEW.dean_lecturer_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM lecturers l JOIN departments d ON d.department_id = l.department_id
        WHERE l.lecturer_id = NEW.dean_lecturer_id AND d.faculty_id = NEW.faculty_id) THEN
        RAISE EXCEPTION 'the dean must be a lecturer in one of the faculty''s departments'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_faculty_dean';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_faculty_guard BEFORE INSERT OR UPDATE ON faculties
    FOR EACH ROW EXECUTE FUNCTION faculty_guard();

-- R18: ...and the same rule from the department side: a dean cannot be
-- appointed head. Keeping the two posts apart guarantees an approver other
-- than the marker for every result (R17).
CREATE FUNCTION department_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    IF NEW.head_lecturer_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM faculties WHERE dean_lecturer_id = NEW.head_lecturer_id) THEN
        RAISE EXCEPTION 'a dean cannot also be a head of department'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_dean_not_head';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_department_guard BEFORE INSERT OR UPDATE ON departments
    FOR EACH ROW EXECUTE FUNCTION department_guard();

-- R17: who may approve or amend a course's results: the head of the
-- course's department, or the faculty dean when the head entered the result.
-- A dean is never a head (R18), so the approver is never the marker. NULL if
-- that post is vacant: nobody can approve until it is filled.
CREATE FUNCTION result_authority(p_course integer, p_entered_by integer)
RETURNS integer
LANGUAGE sql STABLE
SET search_path = pg_catalog, public, pg_temp AS $$
    SELECT CASE WHEN d.head_lecturer_id = p_entered_by THEN f.dean_lecturer_id
                ELSE d.head_lecturer_id END
    FROM courses c
    JOIN departments d ON d.department_id = c.department_id
    JOIN faculties f   ON f.faculty_id = d.faculty_id
    WHERE c.course_id = p_course
$$;

-- R6: a prerequisite must be a lower-level course. This also rules out
-- cycles (A needs B needs A), since levels strictly decrease along a chain.
CREATE FUNCTION prerequisite_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_course_level smallint;
    v_prereq_level smallint;
BEGIN
    IF NEW.course_id = NEW.prerequisite_id THEN
        RETURN NEW;                       -- reported by chk_prereq_not_self
    END IF;
    SELECT level INTO v_course_level FROM courses WHERE course_id = NEW.course_id;
    SELECT level INTO v_prereq_level FROM courses WHERE course_id = NEW.prerequisite_id;
    IF v_prereq_level >= v_course_level THEN
        RAISE EXCEPTION 'prerequisite must be a lower-level course (% level is not below % level)',
            v_prereq_level, v_course_level
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_prerequisite_level';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_prerequisite_guard BEFORE INSERT OR UPDATE ON course_prerequisites
    FOR EACH ROW EXECUTE FUNCTION prerequisite_guard();

-- R7: a course is offered only in the term it belongs to, and an offering's
-- capacity can never fall below the students already registered on it.
CREATE FUNCTION offering_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_course_term   text;
    v_semester_term text;
    v_registered    integer;
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.course_id, NEW.semester_id) IS DISTINCT FROM (OLD.course_id, OLD.semester_id) THEN
        RAISE EXCEPTION 'offering %: course and semester cannot be changed', OLD.offering_id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_offering_immutable';
    END IF;
    SELECT term INTO v_course_term FROM courses WHERE course_id = NEW.course_id;
    SELECT term INTO v_semester_term FROM semesters WHERE semester_id = NEW.semester_id;
    IF v_course_term <> v_semester_term THEN
        RAISE EXCEPTION 'course is taught in the % semester, not the %', v_course_term, v_semester_term
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_offering_term';
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.capacity < OLD.capacity THEN
        SELECT count(*) INTO v_registered FROM registrations
        WHERE offering_id = NEW.offering_id AND status = 'registered';
        IF NEW.capacity < v_registered THEN
            RAISE EXCEPTION 'capacity % is below the % students already registered', NEW.capacity, v_registered
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_offering_capacity';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_offering_guard BEFORE INSERT OR UPDATE ON course_offerings
    FOR EACH ROW EXECUTE FUNCTION offering_guard();

-- R15: semesters move forward one stage at a time, and a semester cannot be
-- closed while any registered student is still without an approved result.
CREATE FUNCTION semester_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_stages  text[] := ARRAY['planned', 'registration_open', 'teaching', 'grading', 'closed'];
    v_missing integer;
BEGIN
    IF (NEW.session_id, NEW.term) IS DISTINCT FROM (OLD.session_id, OLD.term) THEN
        RAISE EXCEPTION 'semester %: session and term cannot be changed', OLD.semester_id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_semester_immutable';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status
       AND array_position(v_stages, NEW.status) <> array_position(v_stages, OLD.status) + 1 THEN
        RAISE EXCEPTION 'semester % cannot move from % to %', OLD.semester_id, OLD.status, NEW.status
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_semester_order';
    END IF;
    IF NEW.status = 'closed' AND OLD.status <> 'closed' THEN
        SELECT count(*) INTO v_missing
        FROM registrations g
        JOIN course_offerings o ON o.offering_id = g.offering_id
        LEFT JOIN results r     ON r.registration_id = g.registration_id
        WHERE o.semester_id = NEW.semester_id
          AND g.status = 'registered'
          AND (r.result_id IS NULL OR r.status <> 'approved');
        IF v_missing > 0 THEN
            RAISE EXCEPTION 'semester % cannot close: % registrations have no approved result', OLD.semester_id, v_missing
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_semester_close';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_semester_guard BEFORE UPDATE ON semesters
    FOR EACH ROW EXECUTE FUNCTION semester_guard();

-- New semesters always start at 'planned' (R15).
CREATE FUNCTION semester_insert_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    IF NEW.status <> 'planned' THEN
        RAISE EXCEPTION 'a new semester starts as planned, not %', NEW.status
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_semester_new_planned';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_semester_insert_guard BEFORE INSERT ON semesters
    FOR EACH ROW EXECUTE FUNCTION semester_insert_guard();

-- R8–R13: registering a student on a course.
-- Locks: the offering row (so two students cannot both take the last seat)
-- and the student row (so two of one student's registrations cannot both
-- slip under the unit limit), at every isolation level. Portfolio 3
-- demonstrates why.
CREATE FUNCTION registration_insert_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_off          course_offerings%ROWTYPE;
    v_course       courses%ROWTYPE;
    v_sem_status   text;
    v_stu_status   text;
    v_taken        integer;
    v_units        integer;
    v_missing      text;
    c_max_units    CONSTANT integer := 24;
BEGIN
    IF NEW.status <> 'registered' THEN
        RAISE EXCEPTION 'a new registration must have status registered'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_new';
    END IF;

    -- Each lock is taken with a no-op UPDATE rather than SELECT ... FOR UPDATE.
    -- Under READ COMMITTED both make concurrent registrations wait their turn.
    -- Under REPEATABLE READ or SERIALIZABLE only a write is a conflict: a
    -- transaction whose snapshot predates another's committed registration
    -- then fails with a serialization error instead of counting stale rows.
    UPDATE course_offerings SET capacity = capacity WHERE offering_id = NEW.offering_id;
    UPDATE students SET status = status WHERE student_id = NEW.student_id;
    SELECT * INTO v_off FROM course_offerings WHERE offering_id = NEW.offering_id;
    SELECT * INTO v_course FROM courses WHERE course_id = v_off.course_id;
    SELECT status INTO v_sem_status FROM semesters WHERE semester_id = v_off.semester_id;
    SELECT status INTO v_stu_status FROM students WHERE student_id = NEW.student_id;

    IF v_sem_status <> 'registration_open' THEN
        RAISE EXCEPTION 'registration for this semester is not open (status %)', v_sem_status
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_window';
    END IF;
    IF v_stu_status <> 'active' THEN
        RAISE EXCEPTION 'student % is % and cannot register', NEW.student_id, v_stu_status
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_student_active';
    END IF;

    SELECT count(*) INTO v_taken FROM registrations
    WHERE offering_id = NEW.offering_id AND status = 'registered';
    IF v_taken >= v_off.capacity THEN
        RAISE EXCEPTION '% is full (% of % places taken)', v_course.code, v_taken, v_off.capacity
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_capacity';
    END IF;

    SELECT coalesce(sum(c.units), 0) INTO v_units
    FROM registrations g
    JOIN course_offerings o ON o.offering_id = g.offering_id
    JOIN courses c          ON c.course_id = o.course_id
    WHERE g.student_id = NEW.student_id AND g.status = 'registered'
      AND o.semester_id = v_off.semester_id;
    IF v_units + v_course.units > c_max_units THEN
        RAISE EXCEPTION 'unit limit: % registered + % for % exceeds %',
            v_units, v_course.units, v_course.code, c_max_units
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_unit_limit';
    END IF;

    IF has_passed(NEW.student_id, v_course.course_id) THEN
        RAISE EXCEPTION '% has already been passed', v_course.code
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_already_passed';
    END IF;

    SELECT string_agg(pc.code, ', ' ORDER BY pc.code) INTO v_missing
    FROM course_prerequisites p
    JOIN courses pc ON pc.course_id = p.prerequisite_id
    WHERE p.course_id = v_course.course_id
      AND NOT has_passed(NEW.student_id, p.prerequisite_id);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '% requires a pass in: %', v_course.code, v_missing
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_prerequisite';
    END IF;

    NEW.registered_at := now();
    NEW.dropped_at := NULL;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_registration_insert_guard BEFORE INSERT ON registrations
    FOR EACH ROW EXECUTE FUNCTION registration_insert_guard();

-- R14: the only change to a registration is dropping it, while registration
-- is still open. A drop is final.
CREATE FUNCTION registration_update_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_sem_status text;
BEGIN
    IF (NEW.registration_id, NEW.student_id, NEW.offering_id, NEW.registered_at)
       IS DISTINCT FROM (OLD.registration_id, OLD.student_id, OLD.offering_id, OLD.registered_at)
       OR (NEW.status = OLD.status AND NEW.dropped_at IS DISTINCT FROM OLD.dropped_at) THEN
        RAISE EXCEPTION 'registration %: only its status can change', OLD.registration_id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_immutable';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (OLD.status = 'registered' AND NEW.status = 'dropped') THEN
            RAISE EXCEPTION 'registration % cannot go from % to %', OLD.registration_id, OLD.status, NEW.status
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_drop_final';
        END IF;
        SELECT s.status INTO v_sem_status
        FROM course_offerings o JOIN semesters s ON s.semester_id = o.semester_id
        WHERE o.offering_id = OLD.offering_id;
        -- (Results exist only from the grading stage on, and stages never go
        -- back, so a registration that can still be dropped has no result.)
        IF v_sem_status <> 'registration_open' THEN
            RAISE EXCEPTION 'courses can only be dropped while registration is open (status %)', v_sem_status
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_registration_drop_window';
        END IF;
        NEW.dropped_at := now();          -- set here, never by the caller
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_registration_update_guard BEFORE UPDATE ON registrations
    FOR EACH ROW EXECUTE FUNCTION registration_update_guard();

-- R16, R17: entering and approving results.
--   Entry: only for a registered (not dropped) student, only while the
--   semester is in grading, only by the offering's lecturer, always as draft.
--   Workflow: draft -> submitted -> approved, or submitted -> draft when
--   returned for correction. The score changes only in draft. Approval is by
--   the head of the course's department, never the lecturer who entered it.
--   Once approved, nothing changes (corrections go to result_amendments).
CREATE FUNCTION result_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_reg_status  text;
    v_sem_status  text;
    v_lecturer    integer;
    v_course      integer;
BEGIN
    SELECT g.status, s.status, o.lecturer_id, o.course_id
      INTO v_reg_status, v_sem_status, v_lecturer, v_course
    FROM registrations g
    JOIN course_offerings o ON o.offering_id = g.offering_id
    JOIN semesters s        ON s.semester_id = o.semester_id
    WHERE g.registration_id = NEW.registration_id;

    IF TG_OP = 'INSERT' THEN
        IF v_reg_status <> 'registered' THEN
            RAISE EXCEPTION 'registration % was dropped; no result can be entered', NEW.registration_id
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_registered';
        END IF;
        IF NEW.status <> 'draft' THEN
            RAISE EXCEPTION 'a result is entered as draft, not %', NEW.status
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_new_draft';
        END IF;
        IF NEW.entered_by <> v_lecturer THEN
            RAISE EXCEPTION 'only the lecturer assigned to the course can enter its results'
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_lecturer';
        END IF;
        NEW.entered_at := now();
        NEW.submitted_at := NULL;
        NEW.approved_by := NULL;
        NEW.approved_at := NULL;
    ELSE
        IF OLD.status = 'approved' THEN
            RAISE EXCEPTION 'result % is approved and final; record a correction in result_amendments', OLD.result_id
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_final';
        END IF;
        IF (NEW.result_id, NEW.registration_id, NEW.entered_by, NEW.entered_at)
           IS DISTINCT FROM (OLD.result_id, OLD.registration_id, OLD.entered_by, OLD.entered_at) THEN
            RAISE EXCEPTION 'result %: registration and entry details cannot change', OLD.result_id
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_immutable';
        END IF;
        IF NOT ((OLD.status, NEW.status) IN (('draft', 'draft'), ('draft', 'submitted'),
                                             ('submitted', 'approved'), ('submitted', 'draft'))) THEN
            RAISE EXCEPTION 'result % cannot go from % to %', OLD.result_id, OLD.status, NEW.status
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_workflow';
        END IF;
        IF NEW.score IS DISTINCT FROM OLD.score AND OLD.status <> 'draft' THEN
            RAISE EXCEPTION 'result %: the score can only change while it is a draft', OLD.result_id
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_score_locked';
        END IF;
        IF NEW.status = 'approved'
           AND NEW.approved_by IS DISTINCT FROM result_authority(v_course, OLD.entered_by) THEN
            RAISE EXCEPTION 'only the head of the course''s department (or the dean, if the head marked it) can approve this result'
                USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_approver';
        END IF;
        -- The timestamps are set here, never by the caller.
        NEW.submitted_at := CASE NEW.status WHEN 'draft' THEN NULL
                                            WHEN 'submitted' THEN coalesce(OLD.submitted_at, now())
                                            ELSE OLD.submitted_at END;
        NEW.approved_at  := CASE WHEN NEW.status = 'approved' THEN now() END;
    END IF;

    IF v_sem_status <> 'grading' THEN
        RAISE EXCEPTION 'results can only be entered or changed while the semester is grading (status %)', v_sem_status
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_result_window';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_result_guard BEFORE INSERT OR UPDATE ON results
    FOR EACH ROW EXECUTE FUNCTION result_guard();

-- R19: a correction applies only to an approved result, must change the
-- score, and is made by the same authority that approves results (R17).
CREATE FUNCTION amendment_guard() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_status    text;
    v_current   numeric(5,2);
    v_authority integer;
BEGIN
    SELECT r.status, result_authority(o.course_id, r.entered_by) INTO v_status, v_authority
    FROM results r
    JOIN registrations g    ON g.registration_id = r.registration_id
    JOIN course_offerings o ON o.offering_id = g.offering_id
    WHERE r.result_id = NEW.result_id
    FOR UPDATE OF r;                      -- one correction at a time per result
    IF v_status <> 'approved' THEN
        RAISE EXCEPTION 'result % is not approved; change it through the normal workflow', NEW.result_id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_amendment_approved_only';
    END IF;
    IF NEW.amended_by IS DISTINCT FROM v_authority THEN
        RAISE EXCEPTION 'only the head of the course''s department (or the dean, if the head marked it) can amend this result'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_amendment_by_head';
    END IF;
    SELECT score INTO v_current FROM effective_results WHERE result_id = NEW.result_id;
    SELECT coalesce(max(revision), 0) + 1 INTO NEW.revision
    FROM result_amendments WHERE result_id = NEW.result_id;
    IF NEW.new_score = v_current THEN
        RAISE EXCEPTION 'amendment does not change the score (already %)', v_current
            USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_amendment_changes_score';
    END IF;
    NEW.amended_at := now();
    RETURN NEW;
END $$;
CREATE TRIGGER trg_amendment_guard BEFORE INSERT ON result_amendments
    FOR EACH ROW EXECUTE FUNCTION amendment_guard();

-- R21: history is never deleted or rewritten. Registrations and results are
-- never deleted (a drop is a status); amendments are never changed at all.
CREATE FUNCTION reject_change() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    RAISE EXCEPTION '% on % is not allowed: academic records are permanent', TG_OP, TG_TABLE_NAME
        USING ERRCODE = 'check_violation', CONSTRAINT = 'trg_records_permanent';
END $$;
CREATE TRIGGER trg_registrations_no_delete BEFORE DELETE ON registrations
    FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER trg_results_no_delete BEFORE DELETE ON results
    FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER trg_amendments_no_change BEFORE UPDATE OR DELETE ON result_amendments
    FOR EACH ROW EXECUTE FUNCTION reject_change();
-- TRUNCATE: registrations and results are referenced by foreign keys, so
-- they can only be truncated with CASCADE, which always reaches
-- result_amendments too; this one trigger therefore refuses all three.
CREATE TRIGGER trg_amendments_no_truncate BEFORE TRUNCATE ON result_amendments
    FOR EACH STATEMENT EXECUTE FUNCTION reject_change();

-- ---------------------------------------------------------------------------
-- The grading scale (reference data, part of the schema)
-- ---------------------------------------------------------------------------

INSERT INTO grade_scale (grade, min_score, max_score, points) VALUES
    ('A', 70.00, 100.00, 5),
    ('B', 60.00,  69.99, 4),
    ('C', 50.00,  59.99, 3),
    ('D', 45.00,  49.99, 2),
    ('E', 40.00,  44.99, 1),
    ('F',  0.00,  39.99, 0);

-- ---------------------------------------------------------------------------
-- Least privilege: the role the portal application runs as
-- ---------------------------------------------------------------------------
-- Table owners and superusers can disable triggers, so the application must
-- never connect as one. portal_app can read everything; it can insert only
-- the columns a user supplies (never an identity key, a status the workflow
-- sets, or a timestamp), update only the columns its workflows change, and
-- delete nothing. It cannot create temporary tables. NOLOGIN: the portal's
-- login role is granted membership of it.

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'portal_app') THEN
        CREATE ROLE portal_app NOLOGIN;
    END IF;
    EXECUTE format('REVOKE TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
END $$;

GRANT USAGE ON SCHEMA public TO portal_app;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO portal_app;

GRANT INSERT (code, name)                                     ON faculties            TO portal_app;
GRANT INSERT (faculty_id, code, name)                         ON departments          TO portal_app;
GRANT INSERT (department_id, code, name, award, duration_years) ON programmes         TO portal_app;
GRANT INSERT (department_id, staff_no, first_name, last_name, email) ON lecturers     TO portal_app;
GRANT INSERT (name, starts_on, ends_on)                       ON academic_sessions    TO portal_app;
GRANT INSERT (session_id, term)                               ON semesters            TO portal_app;
GRANT INSERT (matric_no, first_name, last_name, email, programme_id, entry_session_id) ON students TO portal_app;
GRANT INSERT (department_id, code, title, units, level, term) ON courses              TO portal_app;
GRANT INSERT (course_id, prerequisite_id)                     ON course_prerequisites TO portal_app;
GRANT INSERT (course_id, semester_id, lecturer_id, capacity)  ON course_offerings     TO portal_app;
GRANT INSERT (student_id, offering_id)                        ON registrations        TO portal_app;
GRANT INSERT (registration_id, score, entered_by)             ON results              TO portal_app;
GRANT INSERT (result_id, new_score, reason, amended_by)       ON result_amendments    TO portal_app;

GRANT UPDATE (dean_lecturer_id)                               ON faculties        TO portal_app;
GRANT UPDATE (head_lecturer_id)                               ON departments      TO portal_app;
GRANT UPDATE (email)                                          ON lecturers        TO portal_app;
GRANT UPDATE (email, status)                                  ON students         TO portal_app;
GRANT UPDATE (status)                                         ON semesters        TO portal_app;
GRANT UPDATE (lecturer_id, capacity)                          ON course_offerings TO portal_app;
GRANT UPDATE (status)                                         ON registrations    TO portal_app;
GRANT UPDATE (score, status, approved_by)                     ON results          TO portal_app;

COMMIT;
