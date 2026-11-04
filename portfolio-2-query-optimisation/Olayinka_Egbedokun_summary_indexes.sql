-- Wavers University — Portfolio 2: indexes on the precomputed standing
--
--   Q4S (top 10 of one programme): (programme_id, cgpa DESC, matric_no) holds
--   each programme's students already in dean's-list order, so the query
--   reads the first ten entries and stops.
--   Q5S (CGPA below 1.50): (cgpa, matric_no) holds students in CGPA order,
--   so the query reads only the entries below the threshold.
--   The unique index on student_id also allows REFRESH ... CONCURRENTLY,
--   which keeps the view readable while it is rebuilt.

CREATE UNIQUE INDEX uq_standing_student ON student_standing (student_id);
CREATE INDEX ix_standing_programme_cgpa ON student_standing (programme_id, cgpa DESC, matric_no);
CREATE INDEX ix_standing_cgpa ON student_standing (cgpa, matric_no);
ANALYZE student_standing;
