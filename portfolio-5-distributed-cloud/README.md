# Portfolio 5: Distributed and Cloud Database

The Wavers University database run as two PostgreSQL 18.6 servers in
Docker: a primary that takes every write, and a streaming replica that
copies it. Four scenarios show replication, the consistency it gives, the
trade-off of making it synchronous, and failover. Sharding and a cloud
deployment are discussed, not built.

## How to reproduce

```bash
bash portfolio-5-distributed-cloud/Olayinka_Egbedokun_reproduce.sh
```

It starts a fresh primary and replica from this folder's
[compose.yml](compose.yml) (separate from the main one, so Portfolios 1–4
are unaffected), loads the Portfolio 1 schema and Portfolio 2 seed on the
primary, runs the four scenarios and checks every outcome listed below,
writing each log to [evidence/](evidence/). Any other outcome stops the run.
Timings and WAL positions differ from run to run, so the script checks
them against limits (for example, "within a second"), not exact values.

## The set-up

- **Primary** ([primary_init.sh](Olayinka_Egbedokun_primary_init.sh)): a
  `replicator` role allowed to stream the write-ahead log (WAL), the
  primary's record of every change.
- **Replica** ([replica_start.sh](Olayinka_Egbedokun_replica_start.sh)):
  on first start, `pg_basebackup` copies the primary and creates a
  replication slot, so the primary keeps any WAL the replica has not
  received yet. The replica then runs as a read-only *hot standby*,
  receiving and applying the WAL as it arrives.

The replica is cloned before any data exists; the schema and seed loaded
afterwards reach it through replication alone. The script compares the two
servers with a fingerprint of every row of every table (excluding the
timestamp columns, which are set when a row is written and so differ
between runs), and checks that they are identical.

Every scenario changes the same record: the head of Computer Science
corrects Zainab's CSC101 score ([correction.sql](Olayinka_Egbedokun_correction.sql),
a Portfolio 1 amendment), which changes her CGPA.

## The scenarios

| # | What is done | What happens | Shows | Evidence |
|---|---|---|---|---|
| 1 | A correction committed on the primary; then the same correction sent to the replica | The replica shows the new CGPA within a fraction of a second. The replica refuses the write: "cannot execute INSERT in a read-only transaction" | Replication; all writes go to the primary | [s1_replication](evidence/Olayinka_Egbedokun_s1_replication.txt) |
| 2 | The replica's replay paused, then a correction committed on the primary | The replica has received the change but not applied it: it still shows the old CGPA while the primary shows the new one. Once replay resumes, it catches up | Eventual consistency: a replica can serve stale reads | [s2_eventual](evidence/Olayinka_Egbedokun_s2_eventual.txt) |
| 3 | The replica made synchronous (`synchronous_standby_names`), replay paused, then a correction committed with `synchronous_commit = remote_apply` | The commit does not return: the head's session waits in `SyncRep`, and no other session, on either server, sees the change. Replay is resumed after three seconds; the commit then returns, and the replica already shows the new CGPA | Strong consistency, paid for in waiting | [s3_synchronous](evidence/Olayinka_Egbedokun_s3_synchronous.txt) |
| 3b | Still synchronous; the replica stopped, then a correction committed | The commit waits in `SyncRep` for as long as the replica is offline, and is not visible; when the replica returns, it catches up and the commit returns | Under a partition, synchronous replication gives up write availability | same file |
| 4 | Back to asynchronous. The replica goes offline; a correction is committed on the primary; the primary crashes; the replica returns and is promoted (`pg_promote()`) | The new primary's data is identical (by the fingerprint above) to the primary's before the replica went offline, and it accepts writes. The correction committed while the replica was offline is lost, although the head was told it had committed | Availability through failover, and its data-loss risk | [s4_failover](evidence/Olayinka_Egbedokun_s4_failover.txt) |

## What the scenarios show

**Asynchronous replication (1, 2, 4)** is PostgreSQL's default. A commit
returns as soon as the primary has saved it; the replica follows a moment
later. Writes are fast and do not depend on the replica, but a read from
the replica can be stale (2), and a commit the replica never received is
lost if the primary fails (4).

**Synchronous replication (3)** makes the primary wait for the replica
before a commit returns. With `remote_apply`, a returned commit is already
visible on the replica, so nothing read from it is stale, and no commit the
head has been told about can be lost in a failover. The cost is that the
primary's commits wait whenever the replica is slow or unreachable.

**Consistency against availability.** When the servers cannot reach each
other (a network partition), a system must choose between staying
consistent and staying available: the CAP theorem. Scenario 3b chose
consistency: with the synchronous replica unreachable, the write waited
rather than be accepted without it. Scenario 4 chose availability: with
asynchronous replication the write was accepted, and then lost. Even with
no failure, there is a choice between latency and consistency (the "else"
half of PACELC), which scenario 3 shows: a replica that is merely slow
makes every synchronous commit wait for it, while every asynchronous
commit in the evidence returned in 0.0 s (to the nearest tenth).

**Failover** (4) is what makes the replica worth having for availability:
the portal keeps working after the primary is lost. Two measures describe
it. The *recovery point objective* (RPO) is how much committed data may be
lost: under asynchronous replication, whatever the replica had not yet
received (4); under synchronous replication, nothing that was acknowledged.
The *recovery time objective* (RTO) is how long the portal is down: here,
the time to notice the failure and promote the replica, done by hand. In
production a cluster manager (for example Patroni) or a managed cloud
service detects the failure and promotes automatically. The old primary
cannot simply rejoin: it must be rebuilt, or rewound with `pg_rewind`, as a
replica of the new primary.

## Applied to the portal

| Operation | Served by | Why |
|---|---|---|
| Course registration, entering and approving scores, corrections | Primary | Writes, and the rules that guard them (Portfolio 1), live on the primary |
| Issuing an official transcript or probation letter | Primary | A decision about a student must use current data |
| Students viewing their results, especially in the rush after results are released | Replicas | Read-heavy; a few seconds of staleness is acceptable, and adding replicas adds capacity |

One caveat: a member of staff who has just approved a result should read
back from the primary, or they may not see their own change (2).

For the standby kept for failover, synchronous replication is the right
choice: losing an approved correction (4) is not acceptable for academic
records. To keep one slow or lost standby from stopping every write (3,
3b), use two
standbys and wait for either (`synchronous_standby_names = 'ANY 1 (s1, s2)'`).

## Sharding (discussion)

Sharding splits the rows of a table across servers, so each holds part of
the data. Replication copies all the data; sharding divides it.

**How the portal would be sharded.** The natural key is the student: hash
the student's ID, and keep a student's registrations, results and
corrections on the same shard as the student. A transcript or GPA then
touches one shard. The small, rarely changing tables (faculties,
programmes, courses, offerings, the grade scale) would be copied to every
shard, as *reference tables*. PostgreSQL itself does not shard; the Citus
extension works this way.

**What it would cost.**

- **Rules that span students.** Course capacity counts registrations on
  every shard, so the Portfolio 1 rule that stops two students taking the
  last place would need a lock or transaction across shards.
- **Course and university-wide queries.** A result sheet (Portfolio 2, Q3)
  or the dean's list (Q4) must ask every shard and combine the answers.
- **Multi-student transactions.** Approving a course's results changes
  rows on many shards, which needs two-phase commit, slower and more
  fragile than a local commit.

**Why the portal does not need it.** Sharding is for data or write traffic
too large for one server. Portfolio 2's 4,006 students and 96,042 results
are small for a single server, and even a university many times the size
would fit on one. The
portal's peak load is reads (students checking results), which replicas
serve without sharding's costs.

## Cloud deployment (discussion)

On a managed PostgreSQL service (for example Amazon RDS for PostgreSQL,
Azure Database for PostgreSQL or Google Cloud SQL), the set-up above maps
onto standard features:

- **High availability:** a standby in a second availability zone (a
  separate data centre), updated synchronously, with automatic failover:
  scenarios 3, 3b and 4, with the detection and promotion done by the service.
- **Read replicas:** asynchronous copies for student-facing reads, as in
  scenarios 1 and 2, and able to be added for the results-release peak.
- **Backups and point-in-time recovery:** replication copies mistakes
  too. A wrongly approved batch reaches every replica within a second
  (1), so recovery from it needs backups plus the archived WAL, which let
  the database be restored to the moment before the mistake.
- **Security and location:** a private network with no public address,
  encrypted connections and storage, and passwords kept in a secrets
  manager rather than in files (unlike this local set-up). Student records
  are personal data, so the choice of region must respect the Nigeria Data
  Protection Act 2023's rules on transferring personal data abroad.

## Limitations

- **One machine.** Both servers run on the same computer, so there is no
  real network delay or partition: a paused replay and a stopped container
  stand in for a slow and an unreachable replica.
- **Manual failover.** Detection and promotion are done by the script;
  rejoining the old primary is not shown.
- **Discussion only** for sharding and cloud deployment: neither was run.
