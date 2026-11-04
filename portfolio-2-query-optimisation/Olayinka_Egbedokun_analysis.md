# Wavers University: Query Performance Analysis

Measured on 4,006 students and 96,042 approved results (four semesters),
PostgreSQL 18.6 in Docker. Every figure below is in [evidence/](evidence/);
the full medians are in the
[results table](evidence/Olayinka_Egbedokun_results_table.md).

## Finding 1: per-student and per-course queries are already fast

Q1 (transcript), Q2 (GPA) and Q3 (result sheet) need a small slice of the
data, and Portfolio 1 had already indexed the columns they look up by.
Their baseline plans use those indexes: 256 buffers (Q1, baseline),
880 buffers (Q2, baseline) and 10249 buffers (Q3, baseline), each in a
dozen milliseconds or less.

To show what those indexes are worth, they were removed inside a rolled-back
transaction and the queries run again:

| Index removed | Used by | Buffers with → without |
|---|---|---|
| `uq_registrations_student_offering` (student_id, offering_id) | Q1, Q2 | 256 buffers (Q1, baseline) → 933 buffers (Q1, without_indexes); 880 buffers (Q2, baseline) → 4366 buffers (Q2, without_indexes) |
| `ix_registrations_offering` (offering_id) | Q3 | 10249 buffers (Q3, baseline) → 10775 buffers (Q3, without_indexes) |

Without them, each query reads all 96,042 registrations to find the 24 (or
1,000) it needs, and Q1 and Q2 take several times longer. Q3 changes less,
because most of its work is the 1,000 per-student lookups that follow, not
finding the registrations. Lesson: indexes chosen for keys and foreign keys
at design time already serve the common point queries; the unique
constraint's index does double duty as a lookup index, because its first
column is `student_id`.

## Finding 2: whole-university reports cannot be fixed with an index

Q4 (dean's list) and Q5 (probation list) need every student's CGPA, so they
must read every approved result: 195678 buffers (Q4, baseline) and
194880 buffers (Q5, baseline), about half a second each. Removing the
registration indexes changes nothing for them: 195678 buffers (Q4, without_indexes).
No index can help a query that needs every row.

The plans also show that about 200 ms of each half-second is JIT
compilation (the `JIT: Timing` lines): PostgreSQL compiles a query to
machine code when its estimated cost is high. Run again with `SET jit =
off`, both queries do the same work, 195678 buffers (Q4, jit_off), and take
a little over half the time (the reproduce script checks they are faster): for
queries that finish in under a second, compiling costs more than it saves.

## Finding 3: precompute what is read often and changes rarely

CGPAs change only when results are approved or corrected, a few times a
semester, while dean's lists and probation reports are read far more
often. So the optimisation stores every student's CGPA in a materialized
view (`student_standing`), refreshed after each batch of approvals or
corrections, and answers Q4 and Q5 from it (Q4S, Q5S). On the full data
they return exactly the same rows as Q4 and Q5 (10 and 318 rows), and the
stored CGPA of every student equals the live one
([evidence](evidence/Olayinka_Egbedokun_summary_check.txt)).

| Query | From live results | From the standing, no index | With its indexes |
|---|---|---|---|
| Dean's list | 195678 buffers (Q4, baseline) | 71 buffers (Q4S, summary_noindex) | 13 buffers (Q4S, summary_indexed) |
| Probation | 194880 buffers (Q5, baseline) | 65 buffers (Q5S, summary_noindex) | 52 buffers (Q5S, summary_indexed) |

Half a second becomes about a millisecond or less. On the small standing
table, an index pays off only when the query needs few of its rows: on
(programme_id, cgpa DESC, matric_no) the dean's list reads its 10 rows
already in order and stops, while the probation list returns 318 students,
8% of the table, so its index on (cgpa, matric_no) saves little over
reading the whole 512 kB table.

## Trade-offs

- **Staleness.** The standing is only as fresh as its last refresh. The
  reproduce script makes a correction after a refresh: one student's stored
  CGPA is then wrong, a refresh fixes it
  ([evidence](evidence/Olayinka_Egbedokun_staleness.txt)). So anything that
  decides about a student (a transcript, a probation letter) reads the live
  views; the standing serves lists and dashboards, refreshed after each
  approval batch.
- **Refresh cost.** A refresh recomputes every CGPA: well under a second
  here, slightly longer with the three indexes to maintain (three runs each
  are noisy; medians in the
  [evidence](evidence/Olayinka_Egbedokun_refresh_cost_summary.txt)). Cheap
  at a few refreshes per semester.
- **Space.** The standing and its indexes take under 1 MB
  ([evidence](evidence/Olayinka_Egbedokun_summary_sizes.txt)).

## Recommendations

1. Keep the Portfolio 1 key and foreign-key indexes: the point queries
   depend on them (Finding 1).
2. Serve dean's lists, probation lists and dashboards from the precomputed
   standing, refreshed after every approval or correction batch; serve
   transcripts and individual GPAs from the live views.
3. Run the reporting queries with JIT off (`SET jit = off` in that
   session): measured here at a little over half the time (Finding 2).

## Limitations

- **Synthetic data.** Scores follow a simple two-group pattern (8% of
  students struggling); real cohorts differ. The sizes of the effects would
  change, not their direction.
- **Warm cache, one machine.** Every table and index page was already in
  memory (the plans show no shared reads; Q4 and Q5's large sorts do spill
  to temporary files). Times therefore reflect memory speed. Buffer counts
  carry over to other machines (they were identical across runs); times do
  not.
- **One user.** Concurrent load is Portfolio 3's subject.
