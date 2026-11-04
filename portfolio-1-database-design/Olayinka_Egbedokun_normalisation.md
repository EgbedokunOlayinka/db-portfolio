# Wavers University Student Result Portal: Normalisation

This document starts from the way results are often kept before a
database exists, a single exams-office result sheet, and normalises it
step by step to the schema in
[Olayinka_Egbedokun_schema.sql](Olayinka_Egbedokun_schema.sql). Each step
names the functional dependencies (FDs) involved and the anomaly it
removes.

## 0. The starting point: one result sheet (illustrative rows)

| matric_no | student_name | programme | department | faculty | session | term | course_code | course_title | units | prerequisites | lecturer | score | grade | points |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| WU/2024/0001 | Amaka Nwosu | Computer Science | Computer Science | Science | 2025/2026 | first | CSC201 | Data Structures | 3 | CSC101 | WU/STF/0002 Bola Adeyemi | 64.00 | B | 4 |
| WU/2024/0002 | Tunde Bakare | Computer Science | Computer Science | Science | 2025/2026 | first | CSC201 | Data Structures | 3 | CSC101 | WU/STF/0002 Bola Adeyemi | 51.50 | C | 3 |

Its problems:

- **Update anomaly.** CSC201's title, units and lecturer are repeated on
  every student's row; changing the units means changing every row, and
  missing one leaves the sheet contradicting itself.
- **Insertion anomaly.** A new course cannot be recorded until a student
  has a result in it.
- **Deletion anomaly.** Deleting the last result for a course loses the
  course itself.

## 1. Functional dependencies

From the university's rules (keys written as natural keys). They cover all
the data the portal keeps, including attributes the sheet leaves out, such
as email and status:

| | Dependency | Meaning |
|---|---|---|
| FD1 | matric_no → student_name, email, programme, entry_session, status | A student's details |
| FD2 | email → matric_no | Email is also unique per student |
| FD3 | programme → department, award, duration | A programme belongs to one department |
| FD4 | department → faculty, department_name, head | A department belongs to one faculty |
| FD5 | faculty → faculty_name, dean | |
| FD6 | course_code → course_title, units, level, term, owning department | A course's details |
| FD7 | (course_code, session) → lecturer, capacity | One offering per course per semester |
| FD8 | staff_no → lecturer_name, email, lecturer's department | A lecturer's details |
| FD9 | (matric_no, course_code, session) → score, result status | One result per registration |
| FD10 | score → grade → points | The grading scale |

The sheet's key is (matric_no, course_code, session). The term is not part
of it: a course is taught in one term (FD6), so the course and the session
already fix the semester. (In the schema, an offering refers to a semester,
which is a session and a term, and rule R7 keeps the semester's term equal
to the course's. That is a rule across two tables, enforced by a trigger.)

## 2. First normal form: atomic values, no repeating groups

Two cells are not atomic:

- `prerequisites` holds a list ("CSC101, MTH101" for a course with two).
  A list in a cell cannot be constrained or joined. It moves to its own
  relation, one row per pair:

      COURSE_PREREQUISITE(course_code, prerequisite_code)    key: both

- `lecturer` holds two facts in one value ("WU/STF/0002 Bola Adeyemi").
  It is split into `lecturer_staff_no` and `lecturer_name`.

Every cell now holds one value, so the sheet is in 1NF.

## 3. Second normal form: no partial dependencies on the key

With the key (matric_no, course_code, session), several attributes depend
on only part of it:

- FD1: student details depend on matric_no alone.
- FD6: course details depend on course_code alone.
- FD7: the lecturer depends on (course_code, session), not on the
  student.

Each part becomes its own relation:

    STUDENT(matric_no, student_name, email, programme, department, faculty, entry_session, status)
    COURSE(course_code, course_title, units, level, term, department)
    OFFERING(course_code, session, lecturer_staff_no, lecturer_name, capacity)
    RESULT(matric_no, course_code, session, score, grade, points)

Every non-key attribute now depends on the whole key of its relation: 2NF.

## 4. Third normal form: no transitive dependencies

Some non-key attributes still depend on the key only through another
non-key attribute:

- STUDENT: matric_no → programme → department → faculty (FD1, FD3, FD4).
  The department and faculty move out with the programme:
  `PROGRAMME`, `DEPARTMENT`, `FACULTY`.
- OFFERING: (course, session) → lecturer_staff_no → lecturer_name (FD8).
  The lecturer's details move to `LECTURER`; the offering keeps only the
  staff number.
- RESULT: score → grade → points (FD10). Grade and points depend on the
  score, not on the registration. They move to `GRADE_SCALE`, and since
  they can always be looked up from the score, they are **not stored at
  all**: the views derive them (design decision 1).
- The session and term pair becomes `SEMESTER`, with its own stage
  (`status`), inside `ACADEMIC_SESSION`.
- Registration is separated from result: a student registers before any
  score exists, and may drop the course and never get one. Storing the
  registration in RESULT would bring back the insertion anomaly.

Together with `result_amendments`, which holds corrections (design
decision 3 in the [design document](Olayinka_Egbedokun_database_design.md)),
these are the schema's 14 tables, each in 3NF apart from the deliberate
exception in section 7.

## 5. Boyce–Codd normal form

BCNF requires every determinant to be a candidate key. Checked against
all candidate keys, not just the surrogate primary keys:

| Table | Candidate keys | Other determinants? |
|---|---|---|
| faculties | faculty_id; code; name; dean_lecturer_id | none |
| departments | department_id; code; name; head_lecturer_id | none |
| students | student_id; matric_no; email | none |
| lecturers | lecturer_id; staff_no; email | none |
| courses | course_id; code | none (code → level holds, and code is a key) |
| course_offerings | offering_id; (course_id, semester_id) | none |
| registrations | registration_id; (student_id, offering_id) | status / dropped_at (see below) |
| results | result_id; registration_id | status / timestamps (see below) |
| semesters | semester_id; (session_id, term) | none |
| grade_scale | grade; points; min_score; max_score; score_range | none: the ranges never overlap, so each bound and each range belongs to one grade |
| all others | their identity key and natural key | none |

(`head_lecturer_id` and `dean_lecturer_id` are declared UNIQUE: one post
per person. NULL, a vacant post, may repeat.)

So the schema is in BCNF apart from the two deliberate exceptions below.

## 6. Dependencies that look redundant but are not

- **`results.entered_by` versus `course_offerings.lecturer_id`.** At
  entry they are equal (rule R16), so entered_by might look derivable from
  the offering. It is not: an offering can be reassigned to another
  lecturer later, and entered_by records who actually entered the score.
  It is a historical fact, not a copy.
- **`courses.level`.** It is determined by the code (CSC**2**01 is a
  200-level course). Since `code` is a candidate key, this is a
  dependency on a key and does not break BCNF; `chk_courses_level` makes
  a mismatch impossible.
- **`grade_scale.score_range`.** It is computed from min_score and
  max_score by the database itself (a generated column), so it can never
  disagree with them. It exists because the exclusion constraint and the
  range lookup both need a range value.

## 7. Deliberate exceptions: status columns beside their timestamps

Two tables keep a status that could in principle be read off their
timestamps:

- `registrations.status` is "dropped" exactly when `dropped_at` is set.
- `results.status` follows from the pair (`submitted_at`, `approved_at`):
  draft when neither is set, submitted when only `submitted_at` is,
  approved when both are.

Strictly, that makes the status depend on the key through the timestamp,
a non-key attribute: a transitive dependency, which 3NF, and therefore
BCNF, does not allow. They are kept because the status is what every rule,
query and index uses ("all approved results", "registered students"), and
reading it from timestamp nullness would make every query harder to read
and to index. The usual risk of redundancy, the two values disagreeing, is
removed by constraints: `chk_registrations_dropped`, `chk_results_submitted`
and `chk_results_approved_at` reject any row where they disagree, and the
triggers set the timestamps themselves (rules R14 and R17). The redundancy
is therefore controlled: it cannot cause an anomaly.
