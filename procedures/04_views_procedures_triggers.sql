USE MediCore;

-- ============================================================
-- SECTION 1: VIEWS
-- Reusable query layers — shows schema design thinking
-- ============================================================

-- View 1: Master patient dashboard (used by procedures below)
CREATE OR REPLACE VIEW vw_patient_dashboard AS
SELECT
    p.patient_id,
    p.full_name                                             AS patient_name,
    TIMESTAMPDIFF(YEAR, p.dob, CURDATE())                   AS age,
    p.gender,
    p.blood_type,
    p.city,
    p.state,
    COUNT(a.admission_id)                                   AS total_admissions,
    ROUND(SUM(b.total_amount), 2)                           AS lifetime_billing,
    ROUND(AVG(b.total_amount), 2)                           AS avg_billing,
    MAX(a.admission_date)                                   AS last_admission,
    GROUP_CONCAT(
        DISTINCT a.medical_condition
        ORDER BY a.medical_condition
        SEPARATOR ', ')                                     AS conditions_treated,
    COUNT(CASE WHEN a.admission_type = 'Emergency'
               THEN 1 END)                                  AS emergency_visits,
    COUNT(CASE WHEN b.payment_status = 'Pending'
               OR b.payment_status   = 'Partially Paid'
               THEN 1 END)                                  AS outstanding_bills
FROM Patients   p
JOIN Admissions a  ON p.patient_id   = a.patient_id
JOIN Billing    b  ON a.admission_id = b.admission_id
GROUP BY
    p.patient_id, p.full_name, p.dob,
    p.gender, p.blood_type, p.city, p.state;


-- View 2: Hospital revenue summary (financial reporting layer)
CREATE OR REPLACE VIEW vw_hospital_revenue AS
SELECT
    h.hospital_id,
    h.hospital_name,
    h.type                                                  AS hospital_type,
    h.state,
    h.bed_capacity,
    COUNT(DISTINCT a.admission_id)                          AS total_admissions,
    COUNT(DISTINCT a.patient_id)                            AS unique_patients,
    COUNT(DISTINCT a.doctor_id)                             AS active_doctors,
    ROUND(SUM(b.total_amount), 2)                           AS gross_revenue,
    ROUND(SUM(b.insurance_covered), 2)                      AS insurance_revenue,
    ROUND(SUM(b.patient_paid), 2)                           AS patient_revenue,
    ROUND(SUM(b.total_amount)
        - SUM(b.insurance_covered)
        - SUM(b.patient_paid), 2)                           AS total_outstanding,
    ROUND(AVG(b.total_amount), 2)                           AS avg_bill,
    COUNT(CASE WHEN b.payment_status = 'Pending'
               THEN 1 END)                                  AS pending_payments,
    COUNT(CASE WHEN a.status = 'Critical'
               THEN 1 END)                                  AS critical_patients
FROM Hospitals  h
JOIN Admissions a  ON h.hospital_id  = a.hospital_id
JOIN Billing    b  ON a.admission_id = b.admission_id
GROUP BY
    h.hospital_id, h.hospital_name,
    h.type, h.state, h.bed_capacity;


-- View 3: Active critical patients (operational real-time view)
CREATE OR REPLACE VIEW vw_critical_patients AS
SELECT
    p.patient_id,
    p.full_name                                             AS patient_name,
    p.blood_type,
    p.contact_phone,
    a.admission_id,
    a.admission_date,
    DATEDIFF(CURDATE(), a.admission_date)                   AS days_admitted,
    a.medical_condition,
    a.room_number,
    a.admission_type,
    a.test_results,
    h.hospital_name,
    d.full_name                                             AS doctor_name,
    d.contact_email                                         AS doctor_email,
    b.total_amount,
    b.payment_status
FROM Admissions             a
JOIN Patients               p   ON a.patient_id   = p.patient_id
JOIN Hospitals              h   ON a.hospital_id  = h.hospital_id
JOIN Doctors                d   ON a.doctor_id    = d.doctor_id
JOIN Billing                b   ON a.admission_id = b.admission_id
WHERE a.status IN ('Critical', 'Admitted')
  AND a.discharge_date IS NULL;


-- ============================================================
-- SECTION 2: STORED PROCEDURES
-- Shows you can write reusable, parameterized, production logic
-- ============================================================

-- Procedure 1: Full patient history lookup
--   Input  : patient name (partial match supported)
--   Output : complete history across all admissions
DELIMITER $$

CREATE PROCEDURE sp_patient_history(
    IN  p_name          VARCHAR(150),
    IN  p_start_date    DATE,
    IN  p_end_date      DATE
)
BEGIN
    -- Input validation
    IF p_name IS NULL OR TRIM(p_name) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Patient name cannot be empty.';
    END IF;

    SELECT
        p.patient_id,
        p.full_name                                         AS patient_name,
        TIMESTAMPDIFF(YEAR, p.dob, CURDATE())               AS age,
        p.blood_type,
        a.admission_id,
        a.admission_date,
        a.discharge_date,
        DATEDIFF(
            COALESCE(a.discharge_date, CURDATE()),
            a.admission_date)                               AS los_days,
        a.admission_type,
        a.medical_condition,
        a.test_results,
        a.status                                            AS admission_status,
        d.full_name                                         AS doctor_name,
        d.specialization,
        h.hospital_name,
        t.treatment_name,
        t.medication,
        t.treatment_cost,
        t.outcome                                           AS treatment_outcome,
        b.total_amount,
        b.insurance_covered,
        b.patient_paid,
        b.payment_status
    FROM Patients    p
    JOIN Admissions  a  ON p.patient_id   = a.patient_id
    JOIN Doctors     d  ON a.doctor_id    = d.doctor_id
    JOIN Hospitals   h  ON a.hospital_id  = h.hospital_id
    JOIN Treatments  t  ON a.admission_id = t.admission_id
    JOIN Billing     b  ON a.admission_id = b.admission_id
    WHERE p.full_name LIKE CONCAT('%', p_name, '%')
      AND (p_start_date IS NULL OR a.admission_date >= p_start_date)
      AND (p_end_date   IS NULL OR a.admission_date <= p_end_date)
    ORDER BY a.admission_date ASC, t.treatment_date ASC;
END $$

DELIMITER ;

-- Test it:
CALL sp_patient_history('James Harrington', NULL, NULL);
CALL sp_patient_history('Harrington', '2022-01-01', '2024-12-31');


-- Procedure 2: Hospital revenue report with date range
--   Shows: dynamic filtering, summary + detail in one proc
DELIMITER $$

CREATE PROCEDURE sp_hospital_revenue_report(
    IN  p_hospital_id   INT,
    IN  p_year          INT
)
BEGIN
    DECLARE v_hospital_name VARCHAR(150);

    -- Resolve hospital name for output labeling
    SELECT hospital_name INTO v_hospital_name
    FROM   Hospitals
    WHERE  hospital_id = p_hospital_id;

    IF v_hospital_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Hospital not found.';
    END IF;

    -- Summary block
    SELECT
        v_hospital_name                                     AS hospital,
        p_year                                              AS report_year,
        COUNT(a.admission_id)                               AS total_admissions,
        ROUND(SUM(b.total_amount), 2)                       AS gross_revenue,
        ROUND(SUM(b.insurance_covered), 2)                  AS insured_amount,
        ROUND(SUM(b.patient_paid), 2)                       AS collected_from_patients,
        ROUND(SUM(b.total_amount)
            - SUM(b.insurance_covered)
            - SUM(b.patient_paid), 2)                       AS uncollected,
        COUNT(CASE WHEN b.payment_status = 'Paid'
                   THEN 1 END)                              AS fully_paid_bills,
        COUNT(CASE WHEN b.payment_status != 'Paid'
                   THEN 1 END)                              AS outstanding_bills
    FROM Admissions  a
    JOIN Billing     b  ON a.admission_id = b.admission_id
    WHERE a.hospital_id = p_hospital_id
      AND (p_year IS NULL OR YEAR(a.admission_date) = p_year);

    -- Monthly breakdown
    SELECT
        DATE_FORMAT(a.admission_date, '%Y-%m')              AS month,
        COUNT(a.admission_id)                               AS admissions,
        ROUND(SUM(b.total_amount), 2)                       AS revenue,
        ROUND(SUM(b.insurance_covered), 2)                  AS insured,
        ROUND(SUM(b.patient_paid), 2)                       AS collected
    FROM Admissions  a
    JOIN Billing     b  ON a.admission_id = b.admission_id
    WHERE a.hospital_id = p_hospital_id
      AND (p_year IS NULL OR YEAR(a.admission_date) = p_year)
    GROUP BY DATE_FORMAT(a.admission_date, '%Y-%m')
    ORDER BY month;
END $$

DELIMITER ;

-- Test it:
CALL sp_hospital_revenue_report(4, 2023);
CALL sp_hospital_revenue_report(1, NULL);  -- All years


-- Procedure 3: Blood donor matcher
--   Real clinical use case — finds compatible donors in priority order
DELIMITER $$

CREATE PROCEDURE sp_blood_matcher(
    IN  p_patient_id    INT
)
BEGIN
    DECLARE v_blood_type    VARCHAR(5);
    DECLARE v_patient_name  VARCHAR(150);

    -- Fetch recipient details
    SELECT full_name, blood_type
    INTO   v_patient_name, v_blood_type
    FROM   Patients
    WHERE  patient_id = p_patient_id;

    IF v_patient_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Patient not found.';
    END IF;

    SELECT
        v_patient_name                                          AS recipient_name,
        v_blood_type                                            AS recipient_blood_type,
        donor.full_name                                         AS donor_name,
        donor.blood_type                                        AS donor_blood_type,
        TIMESTAMPDIFF(YEAR, donor.dob, CURDATE())               AS donor_age,
        donor_adm.hospital_id = recip_adm.hospital_id          AS same_hospital,
        h.hospital_name                                         AS donor_hospital,
        CASE
            WHEN donor_adm.hospital_id = recip_adm.hospital_id
            THEN '⭐ Priority — Same Hospital'
            ELSE '   Available — Different Hospital'
        END                                                     AS match_priority
    FROM Patients donor
    -- Compatibility matrix via inline mapping
    JOIN (
        SELECT 'AB+' AS recipient_bt, 'O+'  AS donor_bt UNION ALL
        SELECT 'AB+',  'O-'  UNION ALL SELECT 'AB+',  'A+'  UNION ALL
        SELECT 'AB+',  'A-'  UNION ALL SELECT 'AB+',  'B+'  UNION ALL
        SELECT 'AB+',  'B-'  UNION ALL SELECT 'AB+',  'AB+' UNION ALL
        SELECT 'AB+',  'AB-' UNION ALL
        SELECT 'AB-',  'O-'  UNION ALL SELECT 'AB-',  'A-'  UNION ALL
        SELECT 'AB-',  'B-'  UNION ALL SELECT 'AB-',  'AB-' UNION ALL
        SELECT 'A+',   'O+'  UNION ALL SELECT 'A+',   'O-'  UNION ALL
        SELECT 'A+',   'A+'  UNION ALL SELECT 'A+',   'A-'  UNION ALL
        SELECT 'A-',   'O-'  UNION ALL SELECT 'A-',   'A-'  UNION ALL
        SELECT 'B+',   'O+'  UNION ALL SELECT 'B+',   'O-'  UNION ALL
        SELECT 'B+',   'B+'  UNION ALL SELECT 'B+',   'B-'  UNION ALL
        SELECT 'B-',   'O-'  UNION ALL SELECT 'B-',   'B-'  UNION ALL
        SELECT 'O+',   'O+'  UNION ALL SELECT 'O+',   'O-'  UNION ALL
        SELECT 'O-',   'O-'
    ) compat ON compat.recipient_bt = v_blood_type
             AND compat.donor_bt    = donor.blood_type
    JOIN Admissions donor_adm   ON donor.patient_id    = donor_adm.patient_id
    JOIN Admissions recip_adm   ON recip_adm.patient_id = p_patient_id
    JOIN Hospitals  h           ON donor_adm.hospital_id = h.hospital_id
    WHERE donor.patient_id != p_patient_id
      AND TIMESTAMPDIFF(YEAR, donor.dob, CURDATE()) BETWEEN 18 AND 65
    GROUP BY
        donor.patient_id, donor.full_name, donor.blood_type,
        donor.dob, donor_adm.hospital_id, recip_adm.hospital_id,
        h.hospital_name
    ORDER BY same_hospital DESC, donor_age ASC;
END $$

DELIMITER ;

-- Test it:
CALL sp_blood_matcher(4);   -- Linda Beaumont (AB+) — should get many donors
CALL sp_blood_matcher(5);   -- Robert Tran (O-)    — should get only O- donors


-- ============================================================
-- SECTION 3: TRIGGERS
-- Shows you think about data integrity, not just querying
-- ============================================================

-- Trigger 1: Log every new admission into Audit_Log
DELIMITER $$

CREATE TRIGGER trg_after_admission_insert
AFTER INSERT ON Admissions
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, operation, record_id, notes)
    VALUES (
        'Admissions',
        'INSERT',
        NEW.admission_id,
        CONCAT(
            'Patient ID ', NEW.patient_id,
            ' admitted to Hospital ID ', NEW.hospital_id,
            ' on ', NEW.admission_date,
            ' | Condition: ', NEW.medical_condition,
            ' | Type: ', NEW.admission_type
        )
    );
END $$

DELIMITER ;


-- Trigger 2: Log status changes on admissions (Critical → Discharged etc.)
DELIMITER $$

CREATE TRIGGER trg_after_admission_update
AFTER UPDATE ON Admissions
FOR EACH ROW
BEGIN
    IF OLD.status != NEW.status THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, notes)
        VALUES (
            'Admissions',
            'UPDATE',
            NEW.admission_id,
            CONCAT(
                'Status changed from "', OLD.status,
                '" to "', NEW.status,
                '" for Patient ID ', NEW.patient_id,
                ' | Condition: ', NEW.medical_condition
            )
        );
    END IF;
END $$

DELIMITER ;


-- Trigger 3: Prevent billing total less than treatment cost
--   (data integrity guard — shows defensive engineering mindset)
DELIMITER $$

CREATE TRIGGER trg_before_billing_insert
BEFORE INSERT ON Billing
FOR EACH ROW
BEGIN
    DECLARE v_treatment_total DECIMAL(12,2);

    SELECT COALESCE(SUM(treatment_cost), 0)
    INTO   v_treatment_total
    FROM   Treatments
    WHERE  admission_id = NEW.admission_id;

    IF NEW.total_amount < v_treatment_total THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Billing total cannot be less than sum of treatment costs.';
    END IF;
END $$

DELIMITER ;


-- ============================================================
-- Test triggers fired correctly
-- ============================================================

-- This INSERT should auto-log in Audit_Log:
INSERT INTO Admissions
    (patient_id, hospital_id, doctor_id, department_id,
     admission_date, admission_type, room_number,
     medical_condition, test_results, status)
VALUES
    (2, 1, 1, 1, CURDATE(), 'Urgent', 201,
     'Hypertension', 'Normal', 'Admitted');

-- This UPDATE should log the status change:
UPDATE Admissions
SET    status = 'Discharged',
       discharge_date = CURDATE()
WHERE  admission_id = (SELECT MAX(admission_id) FROM (SELECT admission_id FROM Admissions) tmp);

-- Verify audit trail:
SELECT * FROM Audit_Log ORDER BY changed_at DESC LIMIT 10;

-- Test the billing guard trigger (should FAIL with our error):
INSERT INTO Billing
    (admission_id, provider_id, total_amount,
     insurance_covered, patient_paid, payment_status)
VALUES
    ((SELECT MAX(admission_id) FROM (SELECT admission_id FROM Admissions) tmp2),
     1, 100.00, 50.00, 50.00, 'Pending');

-- Clean up the test admission (keeps data clean for Phase 5):
DELETE FROM Admissions
WHERE  medical_condition = 'Hypertension'
  AND  patient_id = 2
  AND  admission_date = CURDATE();