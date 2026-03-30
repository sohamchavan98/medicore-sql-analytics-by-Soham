# MediCore Analytics System
### Advanced MySQL Portfolio Project | Healthcare Domain

![MySQL](https://img.shields.io/badge/MySQL-8.0.41-blue)
![Domain](https://img.shields.io/badge/Domain-Healthcare-green)
![Level](https://img.shields.io/badge/Level-Advanced-red)

## Overview
A fully normalized, multi-table MySQL database simulating a hospital network 
operations and analytics system. Built to demonstrate FAANG-level SQL 
engineering across all major competency areas.

## Database Schema — 9 Tables
| Table | Rows | Purpose |
|---|---|---|
| Hospitals | 6 | Hospital network master data |
| Departments | 18 | Departments per hospital |
| Doctors | 18 | Physician profiles |
| Patients | 30 | Patient demographics |
| Insurance_Providers | 6 | Insurer coverage data |
| Admissions | 40 | Core fact table |
| Treatments | 80 | Procedures per admission |
| Billing | 40 | Financial records |
| Audit_Log | — | Trigger-populated audit trail |

## What's Demonstrated

### 12 Analytical Queries across 6 tiers:
- **Tier 1** — 5-table JOINs, LEFT JOIN, NULL handling
- **Tier 2** — GROUP BY, HAVING, RANK, DENSE_RANK, PERCENT_RANK
- **Tier 3** — CTEs, correlated subqueries, chained multi-CTEs
- **Tier 4** — NTILE, LAG, LEAD, FIRST_VALUE, frame clauses
- **Tier 5** — Recursive CTE for hierarchy traversal
- **Tier 6** — Composite severity scoring with weighted formula

### Production Engineering:
- 4 Views (dashboard, revenue, operational, index metadata)
- 3 Stored Procedures with SIGNAL SQLSTATE error handling
- 3 Triggers (AFTER INSERT/UPDATE audit, BEFORE INSERT data guard)
- 14 Strategic Indexes with composite and covering index patterns
- Query optimization: correlated → CTE, IN → EXISTS, 
  function-on-column → range predicate

## How to Run
1. Run files in numbered order (01 → 05)
2. Requires MySQL 8.0+
3. Each file is self-contained and idempotent

## Files
| File | Contents |
|---|---|
| `schema/01_create_database.sql` | Database + all 9 tables |
| `data/02_seed_data.sql` | Realistic seed data |
| `queries/03_analytical_queries.sql` | 12 FAANG-level queries |
| `procedures/04_views_procedures_triggers.sql` | Views, procs, triggers |
| `optimization/05_indexes_and_optimization.sql` | Indexes + EXPLAIN ANALYZE |
| `docs/MediCore_Portfolio_README.docx` | Full project documentation |