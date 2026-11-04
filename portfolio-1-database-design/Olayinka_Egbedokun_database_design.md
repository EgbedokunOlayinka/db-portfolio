# Wavers University Student Result Portal: Database Design

## 1. The case study

**Wavers University** is a simulated Nigerian university. Its Student
Result Portal is where students register for courses each semester,
lecturers enter scores, heads of department approve results, and the
registry produces GPAs and transcripts.

| | |
|---|---|
| **Nature of the system** | Academic records: who studies what, when, and with what result |
| **Users** | Students (register, view results and transcript); lecturers (enter and submit scores); heads of department and deans (approve and correct results); registry and exams office (calendar, courses, offerings, transcripts) |
| **Major data** | Faculties, departments, programmes, lecturers, students, academic sessions and semesters, courses and prerequisites, course offerings, registrations, results, result corrections, the grading scale |
| **Key operations** | Register courses; drop a course; enter, submit and approve scores; correct an approved result; compute semester GPA and CGPA; generate a transcript |

The grading scale is the Nigerian five-point scale: A (70–100) = 5,
B (60–69) = 4, C (50–59) = 3, D (45–49) = 2, E (40–44) = 1, F (0–39) = 0.
GPA = Σ(grade points × course units) ÷ Σ(course units).

## 2. Entities

The schema ([Olayinka_Egbedokun_schema.sql](Olayinka_Egbedokun_schema.sql))
has 14 tables and 5 views; the
[ER diagram](Olayinka_Egbedokun_er_diagram.md) shows every column and
relationship.

| Area | Tables | Purpose |
|---|---|---|
| Organisation | `faculties`, `departments`, `programmes`, `lecturers` | Who runs what. Each faculty has a dean, each department a head. |
| Calendar | `academic_sessions`, `semesters` | A session (e.g. 2025/2026) has a first and a second semester. A semester's `status` is the stage it is in. |
| People studying | `students` | Matric number, programme, entry session, status. |
| Curriculum | `courses`, `course_prerequisites`, `course_offerings` | A course (e.g. CSC201, 3 units) is taught in one term; an offering is that course in one semester, with a lecturer and a capacity. |
| Records | `registrations`, `results`, `result_amendments` | A student registers on an offering; the registration gets one result; corrections to an approved result are added as amendments. |
| Reference | `grade_scale` | Score ranges, grades and points. |
| Derived (views) | `effective_results`, `graded_courses`, `semester_gpa`, `student_cgpa`, `transcript` | The score that counts, grades, GPA, CGPA and the transcript, all computed when read. |

## 3. Business rules and how each is enforced

"Tests" are the rule tests in
[Olayinka_Egbedokun_constraint_tests.sql](Olayinka_Egbedokun_constraint_tests.sql):
T = a breaking statement that must be rejected by that exact rule,
P = valid work that must be accepted with exactly the right result.

| # | Rule | Enforced by | Tests |
|---|---|---|---|
| R1 | A student has a unique, well-formed matric number (WU/yyyy/nnnn) and a unique lower-case email; names are not blank; status is one of four values; the programme exists | `uq_students_matric_no`, `chk_students_matric_no`, `uq_students_email`, `chk_students_email`, `chk_students_names`, `chk_students_status`, `fk_students_programme` | T01–T07 |
| R2 | A lecturer has a unique, well-formed staff number and a unique lower-case email | `uq_lecturers_staff_no`, `chk_lecturers_staff_no`, `uq_lecturers_email`, `chk_lecturers_email` | T08–T10, T87 |
| R3 | Faculty and department codes are unique and well-formed; a programme code is unique and well-formed (CSC-BSC), and no two programmes share both name and award; awards come from a fixed list | `chk_faculties_code`, `uq_departments_code`, `chk_programmes_code`, `uq_programmes_name_award`, `chk_programmes_award` | T11–T13, T74, T75 |
| R4 | A course code is unique and well-formed (CSC201); units are 1–6; the level is the code's first digit × 100 | `uq_courses_code`, `chk_courses_code`, `chk_courses_units`, `chk_courses_level` | T14–T17 |
| R5 | A session is named YYYY/YYYY+1 and ends after it starts; it has at most one first and one second semester | `chk_academic_sessions_name`, `chk_academic_sessions_dates`, `uq_semesters_session_term` | T18–T20 |
| R6 | A prerequisite is a different, lower-level course, so prerequisite chains can never loop | `chk_prereq_not_self`, trigger `trg_prerequisite_level` | T21–T23 |
| R7 | A course is offered at most once per semester, only in its own term, with a capacity above 0 that never falls below the students registered; an offering's course and semester never change | `uq_offerings_course_semester`, trigger `trg_offering_term`, `chk_offerings_capacity`, trigger `trg_offering_capacity`, trigger `trg_offering_immutable` | T24–T26, T28, T85 |
| R8 | Students register only while the semester's registration is open | trigger `trg_registration_window` | T32 |
| R9 | Only active students register | trigger `trg_registration_student_active` | T33 |
| R10 | An offering never has more registered students than its capacity, even when students register at the same moment | trigger `trg_registration_capacity`, which first writes to the offering row (decision 5) | T34 |
| R11 | A student registers for at most 24 units in a semester | trigger `trg_registration_unit_limit`, which first writes to the student row (decision 5) | T35, P11 |
| R12 | A student registers for a course only after passing its prerequisites | trigger `trg_registration_prerequisite` | T36, P09 |
| R13 | A passed course cannot be taken again (a failed one can); one registration per student per offering; a new registration is always "registered" | trigger `trg_registration_already_passed`, `uq_registrations_student_offering`, trigger `trg_registration_new` | T37–T39, P10 |
| R14 | The only change to a registration is dropping it, and only while registration is open (results exist only from the grading stage, so a course that can still be dropped never has one); a drop is final and its time is set by the database | triggers `trg_registration_drop_final`, `trg_registration_drop_window`, `trg_registration_immutable` | T40–T42, T73, P01 |
| R15 | A semester starts as planned and moves forward one stage at a time (planned, registration open, teaching, grading, closed); its session and term never change; it cannot close while a registered student lacks an approved result | triggers `trg_semester_new_planned`, `trg_semester_order`, `trg_semester_immutable`, `trg_semester_close` | T27, T29–T31, T86, P08 |
| R16 | A score is 0–100; one result per registration; a result is entered only for a registered (not dropped) student, while the semester is in grading, by the offering's lecturer, as a draft | `chk_results_score`, `uq_results_registration`, triggers `trg_result_registered`, `trg_result_window`, `trg_result_lecturer`, `trg_result_new_draft` | T43, T44, T49, T50, T70, T71 |
| R17 | A result goes draft → submitted → approved (or back to draft for correction); the score changes only in draft and who entered it never changes; the head of the course's department approves, or the dean when the head marked it, so nobody approves their own marking; an approver is recorded only on an approved result; an approved result is final | triggers `trg_result_workflow`, `trg_result_score_locked`, `trg_result_immutable`, `trg_result_approver`, `trg_result_final`; `chk_results_approved_by` | T45–T48, T51, T72, T79, T84, P02–P04 |
| R18 | A department's head is one of its own lecturers and a faculty's dean a lecturer in that faculty; one post per person; a dean is never also a head | composite foreign key `fk_departments_head`, trigger `trg_faculty_dean`, `uq_departments_head`, trigger `trg_dean_not_head` | T52, T54, T76–T78 |
| R19 | An approved result is corrected only by adding an amendment, by the same authority that approves (R17), with a reason, and only if the score changes; the latest correction counts; amendments are never edited | triggers `trg_amendment_approved_only`, `trg_amendment_by_head`, `trg_amendment_changes_score`, `trg_records_permanent`; `chk_amendments_reason` | T53, T55–T58, P07, P14 |
| R20 | Grades, GPA and CGPA are derived from scores, never stored; grade ranges never overlap; the grading scale covers every score from 0 to 100 (checked on the scale the schema installs, which the application cannot change) | views; exclusion constraint `ex_grade_scale_no_overlap` | T59, P05, P06, P12 |
| R21 | Academic records are permanent: registrations, results and amendments are never deleted or truncated | trigger `trg_records_permanent` | T60–T63, T88, T89 |
| R22 | The portal application runs as a role that cannot delete, cannot write columns its workflows do not need (including identity keys, statuses and timestamps), cannot switch off the rules, and cannot substitute its own tables for the ones the rules read | role `portal_app` and its column-level grants; every rule function pins its `search_path`; temporary tables revoked | T64–T69, T80–T83, P13, P15 |

## 4. Design decisions

### Decision 1: derived values are computed, not stored

Grades, grade points, GPA and CGPA are views over the scores. A stored GPA
would have to be updated whenever a score, an amendment or the grading
scale changed, and a missed update would put a wrong figure on a
transcript. Computing them on read means they can never disagree with the
scores. Portfolio 2 measures what this costs and how to make it fast.

### Decision 2: results follow an approval workflow inside the database

A result is entered as a draft, submitted, then approved. The database
checks that each step is made by someone entitled to make it: scores are
entered only as the offering's lecturer, and approved only as the head of
the course's department, or as the faculty dean when the head marked the
course. Because a dean is never also a head (R18), the approver is always
someone other than the marker; `chk_results_four_eyes` restates that as a
constraint, as a second line of defence. Timestamps (`submitted_at`,
`approved_at`, `dropped_at`) are set by triggers, never by the caller, so
they cannot be backdated.

What the database cannot know is who is at the keyboard: the lecturer
recorded in `entered_by` or `approved_by` is the one the portal says is
logged in. The rules make sure that recorded person is entitled to the
step; authenticating them is the portal's job (see Limitations).

### Decision 3: corrections are appended, never overwritten

Once approved, a result row never changes. A correction is a new row in
`result_amendments`, with the new score, a reason and who made it. The
`effective_results` view uses the latest amendment. The original score,
every correction, and who made it remain on record, which is what an
examinations audit needs. The same idea governs deletion: records are
permanent (R21).

### Decision 4: stages are explicit, not inferred from dates

Whether registration is open, or scores may be entered, depends on the
semester's `status`, which the registry moves forward one stage at a
time. Checking dates against the clock instead would make the rules
depend on when a statement runs, so the same test could pass today and
fail tomorrow, and a late correction could not be allowed without editing
dates. A status is also visible: anyone can see which stage a semester is
in.

### Decision 5: registration is safe under concurrency

Two students taking the last seat at the same moment could both see one
free place and both register. Before counting, the registration trigger
therefore writes to the offering row (a no-op update), and before adding
up units it writes to the student row. Under READ COMMITTED, the default,
a second registration for the same course or by the same student waits
for the first and then counts it. Under REPEATABLE READ or SERIALIZABLE,
where a transaction keeps reading from the snapshot it started with, the
write turns the race into a conflict: the later transaction fails with a
serialization error instead of counting from a stale snapshot. A plain
`SELECT ... FOR UPDATE` lock is not enough there, because only a write is
a conflict at those levels.

The reproduce script races two sessions for a course's last place at all
three isolation levels: each time exactly one registration succeeds
([evidence](evidence/Olayinka_Egbedokun_concurrency_check.txt)).
Portfolio 3 examines concurrency in depth.

### Decision 6: keys

Every table has a surrogate key (`GENERATED ALWAYS AS IDENTITY`) and keeps
its natural key unique: matric number,
staff number, course code, session name, (course, semester) for an
offering, (student, offering) for a registration. Surrogate keys keep
foreign keys small and let a natural key be corrected without touching
every referencing row; the unique constraints keep the natural keys
trustworthy. The application role has no INSERT privilege on any key
column, so it cannot override the database's numbering (with `OVERRIDING
SYSTEM VALUE`) and every key it creates comes from the database. Every
constraint, and every check a trigger makes, is named, so a rejection says
exactly which rule fired.

### Decision 7: least privilege for the application

Table owners and superusers can disable triggers, so the rules above only
bind a connection that cannot. The `portal_app` role can read everything;
it can insert only the columns a user supplies and update only the columns
its workflows change (for example a result's `score`, `status` and
`approved_by`, but not who entered it); it deletes nothing and cannot
create temporary tables. Every function behind a rule also pins its
`search_path`, so a session cannot slip in a table of its own under a real
table's name. Tests T64–T69 and T80–T83 show the role cannot delete, write
an unlisted column, set its own keys, disable a trigger, turn off trigger
processing or create temporary tables; P13 shows it can still run the full
workflow, and P15 checks its grants as a whole.

## 5. Limitations

- **Who is logged in is the portal's job.** The database records which
  lecturer entered or approved a result and checks that lecturer was
  entitled to; it does not authenticate them. A stricter design would give
  each member of staff a database login and check `current_user`.
- **Vacant posts stop approvals.** If a department has no head (or, for a
  head's own course, the faculty no dean), nobody can approve its results
  until the post is filled, and the semester cannot close. This is
  deliberate: results are never approved by someone not entitled to.
- **A dropped course cannot be added back** in the same semester: the drop
  is final, and the student would need the registry to intervene.
- **The grading scale is only checked for overlap and coverage,** not that
  points fall as scores fall. Only the schema owner can change it.
- **The grading scale is not versioned.** Changing it would regrade past
  results. A real system would date each scale and grade each result by
  the scale in force when it was approved.
- **There is no minimum unit load.** The 24-unit maximum is checked on
  every registration; a minimum can only be judged when registration
  closes, so it belongs in a report, not a constraint.
- **One assigned lecturer per offering.** Courses with several lecturers
  would need an offering-lecturer table.
- **Every attempt counts towards CGPA.** A failed attempt stays on the
  record alongside the later pass, as is common in Nigerian universities;
  a university that replaces failed grades would change the views, not
  the tables.
