-- Wavers University — Portfolio 2, optimisation 2: a precomputed standing
--
-- Q4 (dean's list) and Q5 (probation) need every student's CGPA, so they
-- must read every approved result however the query is written. But CGPAs
-- only change when results are approved or corrected, a few times a
-- semester, while these lists are read far more often. So the CGPA of every
-- student is computed once and stored in a materialized view, refreshed
-- after each batch of approvals or corrections. Its indexes are created
-- separately (Olayinka_Egbedokun_summary_indexes.sql) so the plans can be
-- measured without and with them.

CREATE MATERIALIZED VIEW student_standing AS
SELECT s.student_id,
       s.matric_no,
       s.last_name || ', ' || s.first_name AS student_name,
       s.programme_id,
       c.units_taken,
       c.cgpa
FROM student_cgpa c
JOIN students s ON s.student_id = c.student_id;

GRANT SELECT ON student_standing TO portal_app;
