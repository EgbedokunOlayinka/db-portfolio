# Portfolio 4: NoSQL and Advanced Data Models

A document model of the same Wavers University data in MongoDB 8.0, built
from the PostgreSQL database, queried, indexed and checked against it.

## How to reproduce

```bash
bash portfolio-4-nosql/Olayinka_Egbedokun_reproduce.sh
```

It starts both containers if needed (PostgreSQL 18.6 and MongoDB 8.0.34,
pinned in [compose.yml](../compose.yml)), builds the Portfolio 2 data in
PostgreSQL, exports it to MongoDB and runs every check below, writing the
results to [evidence/](evidence/). Any failed check stops the run.

## The model: one document per student

The portal's most common read is "show me my results": one student's
whole record, every semester, every course, with grades and GPAs. In
PostgreSQL that takes joins across nine tables (through the `transcript`
view). In MongoDB it
is one document in the `student_records` collection, keyed by matric
number:

```text
{ _id: "WU/2024/2001", name: { first, last }, programme: "CSC-BSC", status,
  unitsTaken, unitsPassed, cgpa,
  semesters: [ { session: "2024/2025", term: "first", unitsTaken, gpa,
                 courses: [ { code, title, units, score, grade, points, amended } ] } ] }
```

A full stored example is in
[sample_document](evidence/Olayinka_Egbedokun_sample_document.txt).
Courses are embedded in semesters, and semesters in the student, because
they are always read with their student and never on their own. Scores,
GPAs and the CGPA are stored as exact decimals (`Decimal128`), never as
floating point, so they match PostgreSQL to the last digit.

**Validation.** The collection has a `$jsonSchema` validator
([collection.js](Olayinka_Egbedokun_collection.js)), the document-store
counterpart of Portfolio 1's CHECK constraints: required fields, matric
and course-code formats, scores 0–100, grades A–F, points 0–5, units 1–6.
Two test documents, each breaking one rule (a grade of G; a score of
120), are each rejected with error 121
([validator_test](evidence/Olayinka_Egbedokun_validator_test.txt)).

**Where the data comes from.** PostgreSQL stays the source of truth.
[export.sql](Olayinka_Egbedokun_export.sql) turns every student's approved
results into one JSON document, and `mongoimport` loads them: all 4,006
students ([import_run](evidence/Olayinka_Egbedokun_import_run.txt)).

## Queries, checked against PostgreSQL

Every MongoDB answer ([queries.js](Olayinka_Egbedokun_queries.js)) is
compared line by line with PostgreSQL's answer to the same question
([pg_answers.sql](Olayinka_Egbedokun_pg_answers.sql)). All are identical
([answers_check](evidence/Olayinka_Egbedokun_answers_check.txt)).

| # | Question | MongoDB | Rows |
|---|---|---|---|
| M1 | One student's transcript | `findOne({ _id })`: one document, no joins | 24 |
| M2 | Dean's list: top 10 CGPAs in Computer Science | `find({ programme }).sort({ cgpa: -1, _id: 1 }).limit(10)` | 10 |
| M3 | Everyone who failed CSC211 | `$elemMatch` on the embedded courses, so code and grade must match in the same course | 193 |
| M4 | Every student's quality points and units, recomputed from the embedded courses; and every stored CGPA | `aggregate` with `$unwind` and `$group` | 4,006 each |

M4 checks every student, not just the ones queried: the quality points and
units recomputed from each document's embedded courses, and each stored
CGPA, equal PostgreSQL's for all 4,006 students. (Individual scores,
grades and semester GPAs are compared for the M1 student.)

## Indexes

`explain("executionStats")` before and after two indexes
([indexes.js](Olayinka_Egbedokun_indexes.js),
[explain](evidence/Olayinka_Egbedokun_explain.txt)):

| Query | Index | Documents examined without → with |
|---|---|---|
| M2 | `{ programme: 1, cgpa: -1, _id: 1 }` | 4,006 → 0: the index alone answers it (a covered query), reading 10 entries already in order |
| M3 | `{ "semesters.courses.code": 1, "semesters.courses.grade": 1 }`, a multikey index: one entry per embedded course | 4,006 → 193: only the students who failed |

## Corrections: the cost of a copy

A document model stores data the way it is read, so the same facts live in
two places. When a result is corrected (M5), the correction is made where
the rules are, in PostgreSQL, as a Portfolio 1 amendment. The MongoDB copy
still shows the old CGPA until that student's document is re-exported,
after which the two agree again
([correction](evidence/Olayinka_Egbedokun_correction.txt)). Re-exporting
one student is a single-document replacement, which MongoDB applies
atomically.

## Why this fits, and where it does not

**Why a document model, not the others.** A key-value store would serve a
transcript by matric number just as fast, but could not answer M2 or M3,
which search inside the values. A column-family store suits huge,
write-heavy, analytical data, not small records read whole. A graph model
would suit the prerequisite network, but that is a few dozen courses that
PostgreSQL already handles. The record is a tree read as a whole, which is
what documents are for.

**A good fit for:**

- **Reading a whole record.** A transcript or results page is one read of
  one document, with no joins, and the document grows naturally semester
  by semester. This is what a student portal does most, and it suits
  caching or serving from replicas.
- **Nested, hierarchical data.** A record is a tree (student → semesters →
  courses), which documents represent directly.

**Not a good fit for, so these stay in PostgreSQL:**

- **Rules that span records.** Course capacity, the unit limit,
  prerequisites, the approval workflow and who may change what all involve
  several students, courses or staff at once. Portfolio 1 enforces them
  with constraints, triggers and locks; a validator only checks one
  document's shape.
- **Concurrent updates to shared data.** MongoDB does have multi-document
  ACID transactions (on a replica set, which this single container is
  not). The reason to keep these in PostgreSQL is that the rules they must
  respect, together with the locking that protects them (Portfolios 1 and
  3), are already enforced there; re-implementing them in a second
  database would mean two places to keep correct.
- **Ad hoc questions across the whole university.** These are what SQL
  joins and aggregates are for.

The design therefore uses each model for its strength: PostgreSQL decides
and records, MongoDB serves the read-heavy record view, rebuilt from
PostgreSQL whenever results change.
