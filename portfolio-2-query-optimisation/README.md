# Portfolio 2: Query Processing and Optimisation

Five queries for the portal's key operations, checked for correctness,
then measured at realistic volume, with indexing and one optimisation.
Findings, recommendations and limitations:
**[Olayinka_Egbedokun_analysis.md](Olayinka_Egbedokun_analysis.md)**.

## How to reproduce

```bash
bash portfolio-2-query-optimisation/Olayinka_Egbedokun_reproduce.sh
```

It starts the PostgreSQL 18.6 container if needed, builds a fresh database
(`wavers_p2`) from the Portfolio 1 schema and rewrites every file in
[evidence/](evidence/). It stops with an error if any check fails.

## Files

| File | What it is |
|---|---|
| [Olayinka_Egbedokun_queries.sql](Olayinka_Egbedokun_queries.sql) | The five queries. Prints results, or plans with `-v EXPLAIN='EXPLAIN (ANALYZE, BUFFERS)'` |
| [Olayinka_Egbedokun_seed.sql](Olayinka_Egbedokun_seed.sql) | Six students, seven courses, one correction: small enough to check by hand |
| [Olayinka_Egbedokun_seed_oracle.py](Olayinka_Egbedokun_seed_oracle.py) → [seed_expected.txt](Olayinka_Egbedokun_seed_expected.txt) | The seed's expected query results, computed in Python, independently of SQL |
| [Olayinka_Egbedokun_bulk_load.sql](Olayinka_Egbedokun_bulk_load.sql) | Realistic volume, through the Portfolio 1 rules |
| [Olayinka_Egbedokun_index_experiment.sql](Olayinka_Egbedokun_index_experiment.sql) | Removes two Portfolio 1 indexes (rolled back) to measure what they are worth |
| [Olayinka_Egbedokun_summary.sql](Olayinka_Egbedokun_summary.sql), [summary_indexes.sql](Olayinka_Egbedokun_summary_indexes.sql), [queries_summary.sql](Olayinka_Egbedokun_queries_summary.sql) | The optimisation: a precomputed standing (CGPA per student), its indexes, and Q4/Q5 rewritten to use it |
| [Olayinka_Egbedokun_plan_summary.awk](Olayinka_Egbedokun_plan_summary.awk) | Turns repeated plans into medians |

## The queries

| # | Query | Key operation |
|---|---|---|
| Q1 | One student's transcript | Generate transcript |
| Q2 | One student's GPA per semester and CGPA | Compute GPA |
| Q3 | One course offering's result sheet | Enter and approve grades |
| Q4 | Top 10 CGPAs in a programme (dean's list) | Reporting |
| Q5 | Every student with CGPA below 1.50 (probation) | Reporting |

## How it was tested

| Check | Result | Evidence |
|---|---|---|
| Correct results | On the seed, all five queries return exactly the independently computed results (GPAs, grades, a corrected score, the order of the dean's list) | [seed_results](evidence/Olayinka_Egbedokun_seed_results.txt) |
| Realistic volume | 4,006 students, 96,042 approved results, loaded through every Portfolio 1 rule | [volume](evidence/Olayinka_Egbedokun_volume.txt), [bulk_load_run](evidence/Olayinka_Egbedokun_bulk_load_run.txt) |
| Plans before and after | `EXPLAIN (ANALYZE, BUFFERS)`; one warm-up, then the median of five runs | [results table](evidence/Olayinka_Egbedokun_results_table.md); full plans in `evidence/Olayinka_Egbedokun_plans_*.txt` |
| The optimisation returns the same rows | Q4S and Q5S give exactly the rows of Q4 and Q5 on the full data | [summary_check](evidence/Olayinka_Egbedokun_summary_check.txt) |
| Its costs | Refresh time with and without its indexes; a correction made after a refresh is shown going stale, then caught | [refresh_cost](evidence/Olayinka_Egbedokun_refresh_cost_summary.txt), [staleness](evidence/Olayinka_Egbedokun_staleness.txt) |
| JIT compilation | Q4 and Q5 rerun with `jit = off`; the script checks both are faster | [results table](evidence/Olayinka_Egbedokun_results_table.md) |
| The documents agree with the evidence | Every buffer figure in the analysis, and the volume, are checked against the evidence; times are quoted only approximately, with exact medians in the results table | [doc_claims_check](evidence/Olayinka_Egbedokun_doc_claims_check.txt) |

**Reading the measurements.** *Total* is planning plus execution time,
which is what one call costs. *Buffers* counts buffer accesses (a page
read twice counts twice), so it measures work done. Buffer counts are the
same on every run, while times vary a little between runs and machines;
that is why the analysis argues from buffers and uses times as
illustration.
