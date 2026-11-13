# Advanced Database Systems Portfolio: Wavers University Student Result Portal

MIT 8103 Advanced Database Systems, continuous assessment portfolio.
Olayinka Egbedokun.

## Case study

**Organisation:** Wavers University, a simulated Nigerian university.

**System:** the Student Result Portal, the database behind course
registration, result processing and academic records.

**Users of the database:**

- **Students** register for courses each semester and view their results,
  GPA and transcript.
- **Lecturers** enter and submit scores for the courses they teach.
- **Heads of department and deans** approve results and correct approved
  results.
- **The registry and exams office** manage the academic calendar,
  courses and course offerings, and issue transcripts.

**Major data stored:** faculties, departments, programmes, lecturers,
students, academic sessions and semesters, courses and their
prerequisites, course offerings, course registrations, results and result
corrections, and the grading scale.

**Key operations the database supports:** register for courses, drop a
course, enter and approve scores, correct an approved result, compute
semester GPA and cumulative GPA (CGPA), and generate a transcript.

## Portfolio activities

| Portfolio | Topic | Status |
|---|---|---|
| [Portfolio 1](portfolio-1-database-design/README.md) | Database design and modelling | Complete |
| [Portfolio 2](portfolio-2-query-optimisation/README.md) | Query processing and optimisation | Complete |
| [Portfolio 3](portfolio-3-transactions-concurrency/README.md) | Transactions and concurrency | Complete |
| [Portfolio 4](portfolio-4-nosql/README.md) | NoSQL and advanced data models | Complete |
| [Portfolio 5](portfolio-5-distributed-cloud/README.md) | Distributed and cloud database | Complete |

## Stack and how to run

All databases run in Docker, from [compose.yml](compose.yml), pinned to
exact versions: PostgreSQL 18.6 and MongoDB 8.0.34. Portfolio 5 runs its
own primary and replica from [its own compose file](portfolio-5-distributed-cloud/compose.yml).

```bash
docker compose up -d --wait      # start the database and wait until it is ready
```

Each portfolio has one reproduce script that rebuilds its database from
empty and regenerates every file in its `evidence/` folder, stopping with
an error if any check fails. Each portfolio README lists what is checked
and where the evidence is.

## Repository structure

```text
.
├── portfolio-1-database-design/          # P1: design, schema, rule tests, evidence/
├── portfolio-2-query-optimisation/       # P2: queries, plans, indexing, analysis, evidence/
├── portfolio-3-transactions-concurrency/ # P3: commit, rollback, isolation, lost update, evidence/
├── portfolio-4-nosql/                    # P4: MongoDB document model, queries, indexes, evidence/
├── portfolio-5-distributed-cloud/        # P5: primary and replica, consistency, failover, evidence/
├── compose.yml                           # database services (Docker)
└── README.md
```
