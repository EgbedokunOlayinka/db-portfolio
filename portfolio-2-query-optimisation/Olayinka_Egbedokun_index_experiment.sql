-- Wavers University — Portfolio 2: what the Portfolio 1 indexes are worth
--
-- Q1-Q3 need a small slice of the data, and Portfolio 1 already indexed the
-- columns they look up by:
--   uq_registrations_student_offering (student_id, offering_id): created by
--     the UNIQUE constraint; its first column finds one student's
--     registrations (Q1, Q2).
--   ix_registrations_offering (offering_id): the index on that foreign key;
--     finds one offering's registrations (Q3).
-- This drops both inside a transaction that is rolled back (DDL is
-- transactional in PostgreSQL, so nothing is really lost), and the
-- reproduce script then runs Olayinka_Egbedokun_queries.sql and ROLLBACK.

BEGIN;
ALTER TABLE registrations DROP CONSTRAINT uq_registrations_student_offering;
DROP INDEX ix_registrations_offering;
