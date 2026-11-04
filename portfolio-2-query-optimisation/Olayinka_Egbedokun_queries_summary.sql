-- Wavers University — Portfolio 2: Q4 and Q5 answered from the precomputed
-- standing (Olayinka_Egbedokun_summary.sql). Same output columns and order
-- as Q4 and Q5 in Olayinka_Egbedokun_queries.sql; the reproduce script
-- checks the results are identical.

\if :{?EXPLAIN} \else \set EXPLAIN '' \endif
\if :{?programme} \else \set programme 'CSC-BSC' \endif

\echo '=== Q4S. Dean''s list from the precomputed standing'
:EXPLAIN
SELECT st.matric_no, st.student_name, st.units_taken, st.cgpa
FROM student_standing st
WHERE st.programme_id = (SELECT programme_id FROM programmes WHERE code = :'programme')
ORDER BY st.cgpa DESC, st.matric_no
LIMIT 10;

\echo '=== Q5S. Probation list from the precomputed standing'
:EXPLAIN
SELECT st.matric_no, p.code AS programme, st.units_taken, st.cgpa
FROM student_standing st
JOIN programmes p ON p.programme_id = st.programme_id
WHERE st.cgpa < 1.50
ORDER BY st.cgpa, st.matric_no;
