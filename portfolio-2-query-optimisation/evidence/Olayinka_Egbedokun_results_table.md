| Query | Stage | Buffers | Median total (ms) |
|---|---|---|---|
| Q1 | baseline | 256 | 3.06 |
| Q2 | baseline | 880 | 2.34 |
| Q3 | baseline | 10249 | 11.71 |
| Q4 | baseline | 195678 | 538.23 |
| Q5 | baseline | 194880 | 467.59 |
| Q1 | without_indexes | 933 | 12.99 |
| Q2 | without_indexes | 4366 | 15.85 |
| Q3 | without_indexes | 10775 | 20.64 |
| Q4 | without_indexes | 195678 | 504.57 |
| Q5 | without_indexes | 194880 | 463.46 |
| Q1 | jit_off | 256 | 2.81 |
| Q2 | jit_off | 880 | 2.34 |
| Q3 | jit_off | 10249 | 11.59 |
| Q4 | jit_off | 195678 | 269.11 |
| Q5 | jit_off | 194880 | 253.06 |
| Q4S | summary_noindex | 71 | 0.85 |
| Q5S | summary_noindex | 65 | 0.86 |
| Q4S | summary_indexed | 13 | 0.49 |
| Q5S | summary_indexed | 52 | 0.76 |
