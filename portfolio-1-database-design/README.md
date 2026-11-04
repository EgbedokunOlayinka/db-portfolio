# Portfolio 1: Database Design and Modelling

The relational design of the Wavers University Student Result Portal:
case study, ER diagram, schema, keys, constraints and normalisation, with
every business rule enforced by the database and tested.

| Deliverable | File |
|---|---|
| Case study, entities, business rules, design decisions | [Olayinka_Egbedokun_database_design.md](Olayinka_Egbedokun_database_design.md) |
| ER diagram | [Olayinka_Egbedokun_er_diagram.md](Olayinka_Egbedokun_er_diagram.md) (source: [.mmd](Olayinka_Egbedokun_er_diagram.mmd)) |
| Relational schema: tables, keys, constraints, triggers, views, application role | [Olayinka_Egbedokun_schema.sql](Olayinka_Egbedokun_schema.sql) |
| Normalisation, from a flat result sheet to BCNF | [Olayinka_Egbedokun_normalisation.md](Olayinka_Egbedokun_normalisation.md) |
| Rule tests | [Olayinka_Egbedokun_constraint_tests.sql](Olayinka_Egbedokun_constraint_tests.sql) |
| Data for the concurrency check | [Olayinka_Egbedokun_concurrency_fixture.sql](Olayinka_Egbedokun_concurrency_fixture.sql) |
| One command that rebuilds everything and regenerates the evidence | [Olayinka_Egbedokun_reproduce.sh](Olayinka_Egbedokun_reproduce.sh) |

## How to reproduce

```bash
bash portfolio-1-database-design/Olayinka_Egbedokun_reproduce.sh
```

The script starts the PostgreSQL 18.6 container if it is not running,
builds the schema in a fresh database (`wavers_p1`) and rewrites every
file in [evidence/](evidence/). It stops with an error unless every
check below holds.

## How it was tested

| Check | Result | Evidence |
|---|---|---|
| The server the evidence came from | PostgreSQL 18.6, Docker image `postgres:18.6`; the script fails if the running version differs from the one compose.yml pins | [environment](evidence/Olayinka_Egbedokun_environment.txt) |
| The schema loads in one transaction | 14 tables, 5 views, committed | [schema_run](evidence/Olayinka_Egbedokun_schema_run.txt), [objects](evidence/Olayinka_Egbedokun_objects.txt), [table_definitions](evidence/Olayinka_Egbedokun_table_definitions.txt) |
| The ER diagram matches the schema | 78 of 78 columns and 21 of 21 foreign keys, compared automatically | [er_diagram_check](evidence/Olayinka_Egbedokun_er_diagram_check.txt) |
| Every rule holds | 105 PASS, 0 FAIL | [constraint_tests](evidence/Olayinka_Egbedokun_constraint_tests.txt) |
| The tests can fail | Removing any one of all 14 triggers makes tests fail; with the registration trigger removed, exactly its 8 tests fail | [mutation_check](evidence/Olayinka_Egbedokun_mutation_check.txt) |
| Two students cannot take the same last place | At READ COMMITTED, REPEATABLE READ and SERIALIZABLE, exactly one of two racing registrations succeeds | [concurrency_check](evidence/Olayinka_Egbedokun_concurrency_check.txt) |
| The documents agree with the evidence | Every figure above, and the design document's rule-to-test table, is checked against the evidence by the script | [doc_claims_check](evidence/Olayinka_Egbedokun_doc_claims_check.txt) |
| The application role has only what it needs | Grants per table and column | [privileges](evidence/Olayinka_Egbedokun_privileges.txt) |

**The rule tests.** Each of the 22 business rules (R1–R22, listed in the
[design document](Olayinka_Egbedokun_database_design.md#3-business-rules-and-how-each-is-enforced))
has at least one negative test: a statement that breaks the rule and
passes only if the database rejects it *with that rule's own constraint*.
A rejection for any other reason counts as a failure, so a test cannot
pass by accident. Positive controls check that valid work is accepted and
that derived values are exact: grades for given scores, a semester GPA
worked out by hand (4.50), the effect of a correction (GPA 0.50 → 1.00),
and that every score from 0.00 to 100.00 maps to exactly one grade. The
tests build a small university inside one transaction and roll it back,
so they leave the database empty.

**Testing the tests.** Two further checks guard against tests that always
pass. The harness is first fed a statement that succeeds and one that
fails for the wrong reason, and must mark both as failures (test H0).
Then the mutation check rebuilds the schema once per trigger, each time
without that trigger, and reruns everything: every removal must be caught,
either by a failing test or by the valid scenario breaking. Each check a
trigger makes has its own name, so a test cannot pass through a
neighbouring check of the same trigger.
