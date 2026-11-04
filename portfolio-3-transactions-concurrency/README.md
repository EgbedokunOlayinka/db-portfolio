# Portfolio 3: Transactions and Concurrency

Four scenarios from the portal's everyday work: committing, rolling back,
reading under two isolation levels, and two staff members changing the
same score at the same time. Every scenario runs on the Portfolio 1 schema
with the Portfolio 2 seed, in PostgreSQL 18.6 in Docker; the concurrent
ones use two real database connections at once.

## How to reproduce

```bash
bash portfolio-3-transactions-concurrency/Olayinka_Egbedokun_reproduce.sh
```

It builds a fresh database (`wavers_p3`), runs all four scenarios, writes
each log to [evidence/](evidence/) and checks every outcome listed below;
any other outcome stops the run. In the concurrent scenarios, session B
starts one second after session A, and A waits two seconds inside its
transaction. The script also checks that events happened in that order
(for example, that each first read came before the other session's change,
and that a session blocked by a lock really waited), so a run cannot pass
by accident of timing.

## The scenarios

| # | Scenario | What happens | Shows | Evidence |
|---|---|---|---|---|
| 1 | Amaka registers for three courses in one transaction ([s1_commit.sql](Olayinka_Egbedokun_s1_commit.sql)) | After `COMMIT`, a separate connection sees all three registrations | Atomic commit, visible to other sessions | [s1_commit](evidence/Olayinka_Egbedokun_s1_commit.txt) |
| 2a | Yusuf registers for two courses, then `ROLLBACK` ([s2_rollback.sql](Olayinka_Egbedokun_s2_rollback.sql)) | Nothing remains | Explicit rollback | [s2_rollback](evidence/Olayinka_Egbedokun_s2_rollback.txt) |
| 2b | Kelechi registers for five courses in one transaction; the fifth breaks the 24-unit limit | The database aborts the transaction, refuses even a read until it ends, and turns the `COMMIT` into `ROLLBACK`: none of the four earlier registrations remain | Atomicity: all or nothing, and a rule (consistency) enforced inside the transaction | same file |
| 2c | Ngozi does the same, with a `SAVEPOINT` before the fifth course | `ROLLBACK TO SAVEPOINT` undoes only the failed step; the first four commit | Partial rollback | same file |
| 3 | The registry reads Zainab's CGPA twice in one transaction while the head of department commits a correction to one of her results in between ([s3_registry.sql](Olayinka_Egbedokun_s3_registry.sql), [s3_correction.sql](Olayinka_Egbedokun_s3_correction.sql)) | READ COMMITTED: the second read shows the new CGPA (a non-repeatable read). REPEATABLE READ: both reads agree; the new CGPA is visible once the transaction ends | Isolation levels | [s3_isolation](evidence/Olayinka_Egbedokun_s3_isolation.txt) |
| 4a | The lecturer adds 5 bonus marks and the head adds 3 moderation marks to the same draft score (50.00), each reading the score and writing back their result ([s4_adjust.sql](Olayinka_Egbedokun_s4_adjust.sql)) | Final score 55.00, not 58.00: the head's change is silently overwritten | The **lost update** problem | [s4_lost_update](evidence/Olayinka_Egbedokun_s4_lost_update.txt) |
| 4b | The same, but each reads with `SELECT ... FOR UPDATE` | The head's read waits for the lecturer to commit, then sees 55.00: final 58.00 | Pessimistic locking | same file |
| 4c | The same, plain reads, at REPEATABLE READ | The lecturer's write fails with "could not serialize access due to concurrent update"; retried, it reads 53.00: final 58.00 | Optimistic concurrency control: detect the conflict, then retry | same file |
| 4d | The same, but each does the arithmetic in one statement: `UPDATE results SET score = score + 5` ([s4_atomic.sql](Olayinka_Egbedokun_s4_atomic.sql)) | The head's UPDATE waits for the lecturer's to commit, then applies +3 to 55.00: final 58.00 | Letting the database read and write in one step | same file |

## What the scenarios show

**Why the lost update happens (4a).** Under READ COMMITTED, each statement
sees the latest committed data, but nothing stops two transactions from
reading the same value and both writing a result based on it. The
lecturer read 50.00, the head read 50.00 and wrote 53.00, then the
lecturer wrote 55.00 over it. Both transactions succeeded; one change is
gone, and nothing reports it.

**The three remedies.**

- **Locking (4b)** makes the second reader wait. It suits a short
  read-then-write on a row that is often contended, and never needs a
  retry.
- **Conflict detection (4c)** lets both read freely and aborts the one
  whose snapshot is out of date when it writes. No lock is held between
  reading and writing, but the application must be ready to retry.
  (The write itself still takes a row lock: had the head's transaction
  still been open, the lecturer's write would have waited for it to end,
  and then failed.)
- **One statement (4d)**, when the change is simple arithmetic: at READ
  COMMITTED, an UPDATE that finds the row locked waits, then re-reads the
  newest committed version before applying its change. At REPEATABLE READ
  the same statement fails with a serialization error instead.

**Which level to use.** READ COMMITTED (PostgreSQL's default) suits short
transactions that write. A report that must be consistent with itself,
such as a transcript or a semester summary computed in several queries,
should run at REPEATABLE READ, so every query sees the same snapshot (3).

**Concurrency enforced by the schema itself.** Portfolio 1's registration
rules already defend against the classic race for the last place on a
course: two students registering at once cannot both take it, at READ
COMMITTED, REPEATABLE READ or SERIALIZABLE
([Portfolio 1 evidence](../portfolio-1-database-design/evidence/Olayinka_Egbedokun_concurrency_check.txt),
design decision 5).
