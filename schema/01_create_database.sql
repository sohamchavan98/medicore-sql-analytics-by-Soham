-- ============================================================
--  MediCore Analytics System
--  Phase 1: Database & Schema Design
--  MySQL 8.0.41
-- ============================================================

CREATE DATABASE IF NOT EXISTS MediCore;
USE MediCore;

-- ============================================================
-- TABLE 1: Hospitals
-- ============================================================
CREATE TABLE Hospitals (
    hospital_id     INT             AUTO_INCREMENT PRIMARY KEY,
    hospital_name   VARCHAR(150)    NOT NULL,
    city            VARCHAR(100)    NOT NULL,
    state           VARCHAR(50)     NOT NULL,
    type            ENUM('Public', 'Private', 'Non-Profit') NOT NULL,
    bed_capacity    INT             NOT NULL,
    established_yr  YEAR            NOT NULL,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- TABLE 2: Departments
-- ============================================================
CREATE TABLE Departments (
    department_id   INT             AUTO_INCREMENT PRIMARY KEY,
    hospital_id     INT             NOT NULL,
    dept_name       VARCHAR(100)    NOT NULL,
    floor_number    TINYINT         NOT NULL,
    CONSTRAINT fk_dept_hospital FOREIGN KEY (hospital_id)
        REFERENCES Hospitals(hospital_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- TABLE 3: Doctors
-- ============================================================
CREATE TABLE Doctors (
    doctor_id       INT             AUTO_INCREMENT PRIMARY KEY,
    hospital_id     INT             NOT NULL,
    department_id   INT             NOT NULL,
    full_name       VARCHAR(150)    NOT NULL,
    specialization  VARCHAR(100)    NOT NULL,
    years_exp       TINYINT         NOT NULL,
    contact_email   VARCHAR(150)    UNIQUE NOT NULL,
    joining_date    DATE            NOT NULL,
    status          ENUM('Active', 'On Leave', 'Resigned') DEFAULT 'Active',
    CONSTRAINT fk_doc_hospital   FOREIGN KEY (hospital_id)
        REFERENCES Hospitals(hospital_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_doc_department FOREIGN KEY (department_id)
        REFERENCES Departments(department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- TABLE 4: Patients
-- ============================================================
CREATE TABLE Patients (
    patient_id      INT             AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(150)    NOT NULL,
    dob             DATE            NOT NULL,
    gender          ENUM('Male', 'Female', 'Other') NOT NULL,
    blood_type      ENUM('A+','A-','B+','B-','AB+','AB-','O+','O-') NOT NULL,
    contact_phone   VARCHAR(20),
    contact_email   VARCHAR(150),
    city            VARCHAR(100),
    state           VARCHAR(50),
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- TABLE 5: Insurance Providers
-- ============================================================
CREATE TABLE Insurance_Providers (
    provider_id     INT             AUTO_INCREMENT PRIMARY KEY,
    provider_name   VARCHAR(150)    NOT NULL,
    coverage_type   ENUM('Basic', 'Standard', 'Premium') NOT NULL,
    max_coverage    DECIMAL(12,2)   NOT NULL,
    contact_email   VARCHAR(150)
);

-- ============================================================
-- TABLE 6: Admissions  (core fact table)
-- ============================================================
CREATE TABLE Admissions (
    admission_id        INT             AUTO_INCREMENT PRIMARY KEY,
    patient_id          INT             NOT NULL,
    hospital_id         INT             NOT NULL,
    doctor_id           INT             NOT NULL,
    department_id       INT             NOT NULL,
    admission_date      DATE            NOT NULL,
    discharge_date      DATE,
    admission_type      ENUM('Emergency', 'Elective', 'Urgent') NOT NULL,
    room_number         SMALLINT        NOT NULL,
    medical_condition   VARCHAR(100)    NOT NULL,
    test_results        ENUM('Normal', 'Abnormal', 'Inconclusive'),
    status              ENUM('Admitted', 'Discharged', 'Critical', 'Deceased') DEFAULT 'Admitted',
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_adm_patient    FOREIGN KEY (patient_id)
        REFERENCES Patients(patient_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_adm_hospital   FOREIGN KEY (hospital_id)
        REFERENCES Hospitals(hospital_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_adm_doctor     FOREIGN KEY (doctor_id)
        REFERENCES Doctors(doctor_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_adm_dept       FOREIGN KEY (department_id)
        REFERENCES Departments(department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- TABLE 7: Treatments
-- ============================================================
CREATE TABLE Treatments (
    treatment_id        INT             AUTO_INCREMENT PRIMARY KEY,
    admission_id        INT             NOT NULL,
    treatment_name      VARCHAR(150)    NOT NULL,
    medication          VARCHAR(150),
    dosage              VARCHAR(100),
    treatment_date      DATE            NOT NULL,
    treatment_cost      DECIMAL(10,2)   NOT NULL,
    outcome             ENUM('Successful', 'Ongoing', 'Failed', 'Referred') NOT NULL,
    CONSTRAINT fk_treat_admission FOREIGN KEY (admission_id)
        REFERENCES Admissions(admission_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- TABLE 8: Billing
-- ============================================================
CREATE TABLE Billing (
    bill_id             INT             AUTO_INCREMENT PRIMARY KEY,
    admission_id        INT             NOT NULL UNIQUE,
    provider_id         INT,
    total_amount        DECIMAL(12,2)   NOT NULL,
    insurance_covered   DECIMAL(12,2)   DEFAULT 0.00,
    patient_paid        DECIMAL(12,2)   DEFAULT 0.00,
    payment_status      ENUM('Paid', 'Pending', 'Partially Paid', 'Rejected') DEFAULT 'Pending',
    payment_date        DATE,
    CONSTRAINT fk_bill_admission FOREIGN KEY (admission_id)
        REFERENCES Admissions(admission_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_bill_provider  FOREIGN KEY (provider_id)
        REFERENCES Insurance_Providers(provider_id)
        ON DELETE SET NULL ON UPDATE CASCADE
);

-- ============================================================
-- TABLE 9: Audit Log  (for trigger demo in Phase 5)
-- ============================================================
CREATE TABLE Audit_Log (
    log_id          INT             AUTO_INCREMENT PRIMARY KEY,
    table_name      VARCHAR(100)    NOT NULL,
    operation       ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    record_id       INT             NOT NULL,
    changed_by      VARCHAR(100)    DEFAULT (USER()),
    changed_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    notes           TEXT
);