USE MediCore;

-- ============================================================
-- TIER 1: MULTI-TABLE JOINs + FILTERING
-- The baseline. Must be flawless.
-- ============================================================

-- Q1. Full patient admission summary
--     (tests: 5-table JOIN, aliasing, date functions, CASE)
SELECT
    p.patient_id,
    p.full_name                                         AS patient_name,
    TIMESTAMPDIFF(YEAR, p.dob, CURDATE())               AS current_age,
    p.blood_type,
    h.hospital_name,
    h.state,
    d.full_name                                         AS doctor_name,
    d.specialization,
    dept.dept_name                                      AS department,
    a.admission_date,
    a.discharge_date,
    DATEDIFF(
        COALESCE(a.discharge_date, CURDATE()),
        a.admission_date
    )                                                   AS los_days,       -- Length of Stay
    a.admission_type,
    a.medical_condition,
    a.test_results,
    a.status                                            AS admission_status,
    CASE
        WHEN a.test_results = 'Normal'       THEN 'Cleared for Discharge'
        WHEN a.test_results = 'Abnormal'     THEN 'Needs Immediate Attention'
        WHEN a.test_results = 'Inconclusive' THEN 'Further Tests Required'
        ELSE 'Awaiting Results'
    END                                                 AS clinical_action
FROM Admissions   a
JOIN Patients     p    ON a.patient_id    = p.patient_id
JOIN Hospitals    h    ON a.hospital_id   = h.hospital_id
JOIN Doctors      d    ON a.doctor_id     = d.doctor_id
JOIN Departments  dept ON a.department_id = dept.department_id
ORDER BY a.admission_date DESC;


-- Q2. Billing breakdown per patient with insurance details
--     (tests: LEFT JOIN to catch uninsured, computed columns, COALESCE)
SELECT
    p.full_name                                             AS patient_name,
    a.medical_condition,
    h.hospital_name,
    ip.provider_name                                        AS insurer,
    ip.coverage_type,
    b.total_amount,
    b.insurance_covered,
    b.patient_paid,
    ROUND(b.total_amount - b.insurance_covered - b.patient_paid, 2)
                                                            AS outstanding_balance,
    ROUND((b.insurance_covered / b.total_amount) * 100, 1) AS insurance_coverage_pct,
    b.payment_status,
    COALESCE(b.payment_date, 'Not Yet Paid')                AS payment_date
FROM Billing              b
JOIN Admissions           a  ON b.admission_id  = a.admission_id
JOIN Patients             p  ON a.patient_id    = p.patient_id
JOIN Hospitals            h  ON a.hospital_id   = h.hospital_id
LEFT JOIN Insurance_Providers ip ON b.provider_id = ip.provider_id
ORDER BY b.total_amount DESC;


-- ============================================================
-- TIER 2: AGGREGATIONS + WINDOW FUNCTIONS
-- Where most candidates stumble. This is FAANG bread & butter.
-- ============================================================

-- Q3. Hospital performance scorecard
--     (tests: GROUP BY + multiple aggregates + HAVING)
SELECT
    h.hospital_name,
    h.type                                                  AS hospital_type,
    h.state,
    COUNT(DISTINCT a.admission_id)                          AS total_admissions,
    COUNT(DISTINCT a.patient_id)                            AS unique_patients,
    ROUND(AVG(DATEDIFF(
        COALESCE(a.discharge_date, CURDATE()),
        a.admission_date)), 1)                              AS avg_los_days,
    ROUND(SUM(b.total_amount), 2)                           AS total_revenue,
    ROUND(AVG(b.total_amount), 2)                           AS avg_bill_per_admission,
    ROUND(SUM(b.insurance_covered), 2)                      AS total_insured,
    ROUND(SUM(b.patient_paid), 2)                           AS total_patient_paid,
    COUNT(CASE WHEN a.status = 'Critical'  THEN 1 END)      AS critical_cases,
    COUNT(CASE WHEN a.test_results = 'Abnormal' THEN 1 END) AS abnormal_results
FROM Hospitals  h
JOIN Admissions a  ON h.hospital_id   = a.hospital_id
JOIN Billing    b  ON a.admission_id  = b.admission_id
GROUP BY h.hospital_id, h.hospital_name, h.type, h.state
HAVING total_admissions > 2
ORDER BY total_revenue DESC;


-- Q4. Doctor leaderboard with window-function ranking
--     (tests: RANK, DENSE_RANK, PERCENT_RANK, PARTITION BY)
SELECT
    d.full_name                                             AS doctor_name,
    d.specialization,
    h.hospital_name,
    COUNT(a.admission_id)                                   AS total_patients,
    ROUND(AVG(b.total_amount), 2)                           AS avg_billing,
    ROUND(SUM(b.total_amount), 2)                           AS total_revenue_generated,
    COUNT(CASE WHEN a.test_results = 'Normal' THEN 1 END)   AS normal_outcomes,
    ROUND(
        COUNT(CASE WHEN a.test_results = 'Normal' THEN 1 END)
        / COUNT(a.admission_id) * 100, 1)                  AS success_rate_pct,
    RANK()        OVER (ORDER BY COUNT(a.admission_id) DESC)
                                                            AS rank_by_volume,
    DENSE_RANK()  OVER (ORDER BY SUM(b.total_amount) DESC)
                                                            AS rank_by_revenue,
    ROUND(PERCENT_RANK() OVER (
        ORDER BY COUNT(a.admission_id)), 2)                 AS percentile_by_volume
FROM Doctors    d
JOIN Admissions a  ON d.doctor_id    = a.doctor_id
JOIN Billing    b  ON a.admission_id = b.admission_id
JOIN Hospitals  h  ON d.hospital_id  = h.hospital_id
GROUP BY d.doctor_id, d.full_name, d.specialization, h.hospital_name
ORDER BY total_patients DESC;


-- Q5. Running total & moving average of monthly revenue
--     (tests: date truncation, SUM OVER, AVG OVER with frame clause)
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(b.payment_date, '%Y-%m')                AS payment_month,
        ROUND(SUM(b.total_amount), 2)                       AS monthly_total
    FROM Billing b
    WHERE b.payment_date IS NOT NULL
    GROUP BY DATE_FORMAT(b.payment_date, '%Y-%m')
)
SELECT
    payment_month,
    monthly_total,
    ROUND(SUM(monthly_total) OVER (
        ORDER BY payment_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2)
                                                            AS running_total,
    ROUND(AVG(monthly_total) OVER (
        ORDER BY payment_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)      AS moving_avg_3month
FROM monthly_revenue
ORDER BY payment_month;


-- ============================================================
-- TIER 3: CTEs + SUBQUERIES + CORRELATED QUERIES
-- Tests ability to think in layers — critical for complex pipelines.
-- ============================================================

-- Q6. Patient readmission analysis
--     (tests: CTE, LAG window function, self-referencing logic)
WITH admission_history AS (
    SELECT
        a.patient_id,
        p.full_name,
        a.admission_id,
        a.medical_condition,
        a.admission_date,
        a.discharge_date,
        LAG(a.discharge_date) OVER (
            PARTITION BY a.patient_id
            ORDER BY a.admission_date)                      AS prev_discharge_date,
        LAG(a.medical_condition) OVER (
            PARTITION BY a.patient_id
            ORDER BY a.admission_date)                      AS prev_condition
    FROM Admissions a
    JOIN Patients   p ON a.patient_id = p.patient_id
)
SELECT
    patient_id,
    full_name,
    admission_id,
    medical_condition,
    admission_date,
    prev_discharge_date,
    DATEDIFF(admission_date, prev_discharge_date)           AS days_since_last_discharge,
    prev_condition,
    CASE
        WHEN DATEDIFF(admission_date, prev_discharge_date) <= 30
             THEN '🚨 30-Day Readmission'
        WHEN DATEDIFF(admission_date, prev_discharge_date) <= 90
             THEN '⚠️  90-Day Readmission'
        ELSE 'Routine Admission'
    END                                                     AS readmission_flag
FROM admission_history
WHERE prev_discharge_date IS NOT NULL
ORDER BY days_since_last_discharge ASC;


-- Q7. Patients billed ABOVE their medical condition's average
--     (tests: correlated subquery in WHERE, benchmark comparison)
SELECT
    p.full_name                                             AS patient_name,
    a.medical_condition,
    h.hospital_name,
    ROUND(b.total_amount, 2)                                AS this_bill,
    ROUND((
        SELECT AVG(b2.total_amount)
        FROM   Billing    b2
        JOIN   Admissions a2 ON b2.admission_id  = a2.admission_id
        WHERE  a2.medical_condition = a.medical_condition
    ), 2)                                                   AS condition_avg_bill,
    ROUND(b.total_amount - (
        SELECT AVG(b2.total_amount)
        FROM   Billing    b2
        JOIN   Admissions a2 ON b2.admission_id  = a2.admission_id
        WHERE  a2.medical_condition = a.medical_condition
    ), 2)                                                   AS above_avg_by,
    b.payment_status
FROM Billing    b
JOIN Admissions a  ON b.admission_id = a.admission_id
JOIN Patients   p  ON a.patient_id   = p.patient_id
JOIN Hospitals  h  ON a.hospital_id  = h.hospital_id
WHERE b.total_amount > (
    SELECT AVG(b2.total_amount)
    FROM   Billing    b2
    JOIN   Admissions a2 ON b2.admission_id  = a2.admission_id
    WHERE  a2.medical_condition = a.medical_condition
)
ORDER BY above_avg_by DESC;


-- Q8. Multi-level CTE: Treatment cost vs billing reconciliation
--     (tests: multiple CTEs chained, aggregation across layers)
WITH treatment_totals AS (
    SELECT
        t.admission_id,
        COUNT(t.treatment_id)               AS num_treatments,
        ROUND(SUM(t.treatment_cost), 2)     AS total_treatment_cost,
        GROUP_CONCAT(t.treatment_name
            ORDER BY t.treatment_date
            SEPARATOR ' → ')               AS treatment_journey
    FROM Treatments t
    GROUP BY t.admission_id
),
billing_gap AS (
    SELECT
        b.admission_id,
        b.total_amount                      AS billed_amount,
        tt.total_treatment_cost,
        ROUND(b.total_amount
            - tt.total_treatment_cost, 2)  AS unexplained_gap,
        tt.num_treatments,
        tt.treatment_journey,
        b.payment_status
    FROM Billing         b
    JOIN treatment_totals tt ON b.admission_id = tt.admission_id
)
SELECT
    p.full_name                             AS patient_name,
    a.medical_condition,
    bg.num_treatments,
    bg.total_treatment_cost,
    bg.billed_amount,
    bg.unexplained_gap,
    CASE
        WHEN bg.unexplained_gap > 10000 THEN '🔴 High Gap — Audit Required'
        WHEN bg.unexplained_gap > 3000  THEN '🟡 Moderate Gap'
        ELSE                                 '🟢 Within Normal Range'
    END                                     AS gap_flag,
    bg.treatment_journey,
    bg.payment_status
FROM billing_gap bg
JOIN Admissions  a  ON bg.admission_id = a.admission_id
JOIN Patients    p  ON a.patient_id    = p.patient_id
ORDER BY bg.unexplained_gap DESC;


-- ============================================================
-- TIER 4: ADVANCED WINDOW FUNCTIONS
-- NTILE, LEAD, first/last value — separates senior from mid-level
-- ============================================================

-- Q9. Patient billing segmentation (quartiles)
--     (tests: NTILE, conditional aggregation across segments)
WITH patient_billing AS (
    SELECT
        p.patient_id,
        p.full_name,
        p.blood_type,
        COUNT(a.admission_id)               AS total_admissions,
        ROUND(SUM(b.total_amount), 2)       AS lifetime_spend,
        ROUND(AVG(b.total_amount), 2)       AS avg_spend_per_admission
    FROM Patients   p
    JOIN Admissions a  ON p.patient_id    = a.patient_id
    JOIN Billing    b  ON a.admission_id  = b.admission_id
    GROUP BY p.patient_id, p.full_name, p.blood_type
)
SELECT
    patient_id,
    full_name,
    blood_type,
    total_admissions,
    lifetime_spend,
    avg_spend_per_admission,
    NTILE(4) OVER (ORDER BY lifetime_spend DESC)            AS spend_quartile,
    CASE NTILE(4) OVER (ORDER BY lifetime_spend DESC)
        WHEN 1 THEN 'Platinum — Top 25%'
        WHEN 2 THEN 'Gold    — Top 50%'
        WHEN 3 THEN 'Silver  — Top 75%'
        WHEN 4 THEN 'Bronze  — Bottom 25%'
    END                                                     AS patient_tier,
    ROUND(SUM(lifetime_spend) OVER (), 2)                   AS total_all_patients,
    ROUND(lifetime_spend / SUM(lifetime_spend) OVER () * 100, 2)
                                                            AS pct_of_total_revenue
FROM patient_billing
ORDER BY lifetime_spend DESC;


-- Q10. Admission trends: LEAD to forecast & LAG to compare
--      (tests: LEAD/LAG across time, MoM change calculation)
WITH monthly_admissions AS (
    SELECT
        DATE_FORMAT(admission_date, '%Y-%m')    AS adm_month,
        COUNT(*)                                AS total_admissions,
        COUNT(CASE WHEN admission_type = 'Emergency' THEN 1 END)
                                                AS emergency_count,
        ROUND(AVG(DATEDIFF(
            COALESCE(discharge_date, CURDATE()),
            admission_date)), 1)                AS avg_los
    FROM Admissions
    GROUP BY DATE_FORMAT(admission_date, '%Y-%m')
)
SELECT
    adm_month,
    total_admissions,
    emergency_count,
    avg_los,
    LAG(total_admissions)  OVER (ORDER BY adm_month)        AS prev_month_admissions,
    LEAD(total_admissions) OVER (ORDER BY adm_month)        AS next_month_admissions,
    ROUND(total_admissions - LAG(total_admissions)
          OVER (ORDER BY adm_month), 0)                     AS mom_change,
    ROUND((total_admissions - LAG(total_admissions)
          OVER (ORDER BY adm_month))
        / LAG(total_admissions) OVER (ORDER BY adm_month)
        * 100, 1)                                           AS mom_change_pct,
    FIRST_VALUE(total_admissions) OVER (
        ORDER BY adm_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
                                                            AS first_month_baseline,
    MAX(total_admissions) OVER ()                           AS peak_month_admissions
FROM monthly_admissions
ORDER BY adm_month;


-- ============================================================
-- TIER 5: RECURSIVE CTE
-- Rare in interviews but unforgettable when done right.
-- ============================================================

-- Q11. Doctor seniority ladder (recursive hierarchy simulation)
--      (tests: WITH RECURSIVE, iterative depth traversal)
WITH RECURSIVE seniority_bands AS (
    -- Base case: least experienced doctors (anchor)
    SELECT
        doctor_id,
        full_name,
        specialization,
        years_exp,
        1                   AS band_level,
        CAST(full_name AS CHAR(500)) AS path
    FROM Doctors
    WHERE years_exp BETWEEN 1 AND 7

    UNION ALL

    -- Recursive case: next experience band
    SELECT
        d.doctor_id,
        d.full_name,
        d.specialization,
        d.years_exp,
        sb.band_level + 1,
        CONCAT(sb.path, ' → ', d.full_name)
    FROM Doctors d
    JOIN seniority_bands sb
        ON d.years_exp = sb.years_exp + 7
    WHERE sb.band_level < 4
)
SELECT
    band_level,
    CASE band_level
        WHEN 1 THEN 'Junior     (1–7 yrs)'
        WHEN 2 THEN 'Mid-Level  (8–14 yrs)'
        WHEN 3 THEN 'Senior     (15–21 yrs)'
        WHEN 4 THEN 'Principal  (22+ yrs)'
    END                     AS experience_band,
    full_name,
    specialization,
    years_exp,
    path                    AS seniority_path
FROM seniority_bands
ORDER BY band_level, years_exp;


-- ============================================================
-- TIER 6: ANALYTICAL — Cohort & Condition Severity Scoring
-- This is the kind of query that makes interviewers lean forward.
-- ============================================================

-- Q12. Condition severity index with composite scoring
--      (tests: multi-metric aggregation, weighted scoring, final ranking)
WITH condition_stats AS (
    SELECT
        a.medical_condition,
        COUNT(a.admission_id)                               AS total_cases,
        ROUND(AVG(DATEDIFF(
            COALESCE(a.discharge_date, CURDATE()),
            a.admission_date)), 1)                          AS avg_los,
        ROUND(AVG(b.total_amount), 2)                       AS avg_cost,
        COUNT(CASE WHEN a.admission_type = 'Emergency'
                   THEN 1 END)                              AS emergency_count,
        COUNT(CASE WHEN a.test_results   = 'Abnormal'
                   THEN 1 END)                              AS abnormal_count,
        COUNT(CASE WHEN a.status IN ('Critical','Deceased')
                   THEN 1 END)                              AS critical_count,
        COUNT(CASE WHEN t.outcome        = 'Failed'
                   THEN 1 END)                              AS failed_treatments,
        ROUND(AVG(b.total_amount - b.insurance_covered
                  - b.patient_paid), 2)                     AS avg_outstanding_balance
    FROM Admissions  a
    JOIN Billing     b  ON a.admission_id  = b.admission_id
    JOIN Treatments  t  ON a.admission_id  = t.admission_id
    GROUP BY a.medical_condition
),
severity_scored AS (
    SELECT
        *,
        -- Composite severity score (weighted formula)
        ROUND(
            (emergency_count  / total_cases * 30) +
            (abnormal_count   / total_cases * 25) +
            (critical_count   / total_cases * 25) +
            (avg_los          / 30         * 10) +
            (avg_cost         / 150000     * 10)
        , 2)                                                AS severity_score
    FROM condition_stats
)
SELECT
    medical_condition,
    total_cases,
    avg_los,
    avg_cost,
    emergency_count,
    abnormal_count,
    critical_count,
    failed_treatments,
    avg_outstanding_balance,
    severity_score,
    RANK() OVER (ORDER BY severity_score DESC)              AS severity_rank,
    CASE
        WHEN severity_score >= 40 THEN '🔴 Critical Condition'
        WHEN severity_score >= 25 THEN '🟠 High Risk'
        WHEN severity_score >= 15 THEN '🟡 Moderate Risk'
        ELSE                           '🟢 Manageable'
    END                                                     AS risk_classification
FROM severity_scored
ORDER BY severity_rank;