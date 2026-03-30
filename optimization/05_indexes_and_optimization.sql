USE MediCore;

-- ============================================================
-- SECTION 1: INDEXING STRATEGY
-- Shows you think about performance, not just correctness
-- ============================================================

-- Before adding indexes, let's see what MySQL auto-created
-- (only PRIMARY KEY indexes exist right now)
SHOW INDEX FROM Admissions;
SHOW INDEX FROM Billing;
SHOW INDEX FROM Treatments;
SHOW INDEX FROM Patients;
SHOW INDEX FROM Doctors;

-- ------------------------------------------------------------
-- Admissions: most queried table — needs the most indexes
-- ------------------------------------------------------------

-- Speeds up: patient history lookups, readmission analysis
CREATE INDEX idx_adm_patient_date
    ON Admissions(patient_id, admission_date);

-- Speeds up: hospital performance reports, revenue queries
CREATE INDEX idx_adm_hospital_date
    ON Admissions(hospital_id, admission_date);

-- Speeds up: doctor leaderboard, workload queries
CREATE INDEX idx_adm_doctor
    ON Admissions(doctor_id);

-- Speeds up: condition-based filtering (severity scoring, avg billing)
CREATE INDEX idx_adm_condition
    ON Admissions(medical_condition);

-- Speeds up: status filtering (critical patients view)
CREATE INDEX idx_adm_status_discharge
    ON Admissions(status, discharge_date);

-- ------------------------------------------------------------
-- Billing: heavily joined, payment queries
-- ------------------------------------------------------------

-- Speeds up: revenue reports filtered by payment status
CREATE INDEX idx_bill_payment_status
    ON Billing(payment_status, payment_date);

-- Speeds up: insurance provider revenue analysis
CREATE INDEX idx_bill_provider
    ON Billing(provider_id);

-- Speeds up: billing amount range queries, above-avg analysis
CREATE INDEX idx_bill_amount
    ON Billing(total_amount);

-- ------------------------------------------------------------
-- Treatments: aggregated per admission frequently
-- ------------------------------------------------------------

-- Speeds up: treatment cost rollups per admission
CREATE INDEX idx_treat_admission_date
    ON Treatments(admission_id, treatment_date);

-- Speeds up: outcome-based filtering
CREATE INDEX idx_treat_outcome
    ON Treatments(outcome);

-- ------------------------------------------------------------
-- Patients: name searches, blood type matching
-- ------------------------------------------------------------

-- Speeds up: sp_patient_history name lookup
CREATE INDEX idx_pat_name
    ON Patients(full_name);

-- Speeds up: blood donor matcher procedure
CREATE INDEX idx_pat_blood_type
    ON Patients(blood_type);

-- ------------------------------------------------------------
-- Doctors: specialization and status filtering
-- ------------------------------------------------------------

CREATE INDEX idx_doc_specialization
    ON Doctors(specialization);

CREATE INDEX idx_doc_status
    ON Doctors(status, hospital_id);


-- ============================================================
-- SECTION 2: EXPLAIN ANALYZE
-- Show interviewers you can READ and ACT on query plans
-- ============================================================

-- ------------------------------------------------------------
-- Test 1: Patient history query — BEFORE vs AFTER index impact
-- ------------------------------------------------------------

-- This is what sp_patient_history runs internally:
EXPLAIN ANALYZE
SELECT
    p.full_name,
    a.admission_date,
    a.medical_condition,
    b.total_amount
FROM Patients    p
JOIN Admissions  a  ON p.patient_id   = a.patient_id
JOIN Billing     b  ON a.admission_id = b.admission_id
WHERE p.full_name LIKE '%Harrington%'
  AND a.admission_date BETWEEN '2022-01-01' AND '2024-12-31';


-- ------------------------------------------------------------
-- Test 2: Condition average billing — correlated subquery plan
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    a.medical_condition,
    ROUND(AVG(b.total_amount), 2) AS avg_billing
FROM Admissions  a
JOIN Billing     b ON a.admission_id = b.admission_id
GROUP BY a.medical_condition
ORDER BY avg_billing DESC;


-- ------------------------------------------------------------
-- Test 3: Critical patients view — index on status pays off
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT * FROM vw_critical_patients;


-- ============================================================
-- SECTION 3: QUERY OPTIMIZATION
-- Rewrite slow patterns into fast ones — shows senior thinking
-- ============================================================

-- ------------------------------------------------------------
-- Optimization 1: Replace correlated subquery with JOIN + CTE
-- SLOW VERSION (runs subquery once per row):
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    p.full_name,
    a.medical_condition,
    b.total_amount,
    (SELECT ROUND(AVG(b2.total_amount), 2)
     FROM   Billing    b2
     JOIN   Admissions a2 ON b2.admission_id = a2.admission_id
     WHERE  a2.medical_condition = a.medical_condition
    ) AS condition_avg
FROM Patients    p
JOIN Admissions  a  ON p.patient_id   = a.patient_id
JOIN Billing     b  ON a.admission_id = b.admission_id;

-- FAST VERSION (precomputes averages once in CTE):
EXPLAIN ANALYZE
WITH condition_avg AS (
    SELECT
        a.medical_condition,
        ROUND(AVG(b.total_amount), 2) AS avg_amount
    FROM   Admissions a
    JOIN   Billing    b ON a.admission_id = b.admission_id
    GROUP  BY a.medical_condition
)
SELECT
    p.full_name,
    a.medical_condition,
    b.total_amount,
    ca.avg_amount                   AS condition_avg
FROM Patients      p
JOIN Admissions    a   ON p.patient_id      = a.patient_id
JOIN Billing       b   ON a.admission_id    = b.admission_id
JOIN condition_avg ca  ON a.medical_condition = ca.medical_condition;


-- ------------------------------------------------------------
-- Optimization 2: EXISTS vs IN for large set filtering
-- SLOWER (IN loads full subquery result into memory):
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT p.full_name, p.blood_type
FROM   Patients p
WHERE  p.patient_id IN (
    SELECT a.patient_id
    FROM   Admissions a
    WHERE  a.medical_condition = 'Heart Failure'
);

-- FASTER (EXISTS short-circuits on first match):
EXPLAIN ANALYZE
SELECT p.full_name, p.blood_type
FROM   Patients p
WHERE  EXISTS (
    SELECT 1
    FROM   Admissions a
    WHERE  a.patient_id       = p.patient_id
      AND  a.medical_condition = 'Heart Failure'
);


-- ------------------------------------------------------------
-- Optimization 3: Avoid function on indexed column in WHERE
-- SLOW (function on column kills index usage):
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT *
FROM   Admissions
WHERE  YEAR(admission_date) = 2023;

-- FAST (range scan uses index on admission_date):
EXPLAIN ANALYZE
SELECT *
FROM   Admissions
WHERE  admission_date BETWEEN '2023-01-01' AND '2023-12-31';


-- ------------------------------------------------------------
-- Optimization 4: Covering index query
-- All columns needed are IN the index — zero table lookup
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT patient_id, admission_date, medical_condition
FROM   Admissions
WHERE  patient_id = 1
  AND  admission_date BETWEEN '2022-01-01' AND '2024-12-31';
-- idx_adm_patient_date covers this entirely (Extra: Using index)


-- ============================================================
-- SECTION 4: PERFORMANCE SUMMARY VIEW
-- A view that documents your index strategy — impressive in portfolio
-- ============================================================
CREATE OR REPLACE VIEW vw_index_usage_summary AS
SELECT
    TABLE_NAME,
    INDEX_NAME,
    GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ', ')
                                    AS indexed_columns,
    INDEX_TYPE,
    CASE NON_UNIQUE
        WHEN 0 THEN 'Unique'
        WHEN 1 THEN 'Non-Unique'
    END                             AS uniqueness
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'MediCore'
GROUP BY TABLE_NAME, INDEX_NAME, INDEX_TYPE, NON_UNIQUE
ORDER BY TABLE_NAME, INDEX_NAME;

-- View your full index strategy at a glance:
SELECT * FROM vw_index_usage_summary;