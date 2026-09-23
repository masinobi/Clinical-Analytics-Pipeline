# Automated Clinical Quality & Patient Outcome Data Pipeline

## Project Objective
An end-to-end clinical analytics build on **synthetic patient records generated with
[Synthea](https://github.com/synthetichealth/synthea)**. Raw EHR extracts are loaded into SQL
Server, modelled into operational-efficiency and patient-safety views, visualised in Power BI,
and used as the basis for an event-driven alerting demo that produces care-team briefings for
high-risk cohorts.

> **No real patient data appears anywhere in this repository.** Every record is synthetic.

## Tech Stack & Ecosystem Architecture
- **Data Ingestion & Extraction (ETL):** Synthea Engine, SQL Server (SSMS), Bulk Insert operations with load reconciliation and quarantine.
- **Relational Modeling & Analytic Views:** T-SQL (Advanced CTEs, Window Functions `LEAD`, Conditional Aggregation `MAX(CASE)`, shared SNOMED CT code lists).
- **Business Intelligence:** Power BI Desktop (DirectQuery Model, Time-Series DAX Relationships).
- **Workflow Automation & Intelligent Orchestration:** Zapier Pro, HTTP Webhooks, Google Gemini API. *The LLM step and channel routing live inside Zapier and are not part of this repository - see section 3.*

## Running It
1. In `sql/1.Database_Setup_and_ingestion.sql`, set `@CsvPath` to the folder holding Synthea's CSV output. It is the only machine-specific value in the pipeline.
2. Run the setup script, then `sql/2.analytical_views.sql`.
3. Check the load reconciliation the setup script prints at the end. On the 11,482-patient extract it should read 678,233 encounters, 420,855 conditions and 591,811 medications, with nothing quarantined. A zero in any of the four data tables means that load failed.

The setup script rebuilds the database from scratch, so every view the report depends on is defined in this repository.

## Key Pipeline Deliverables & Engineering Milestones

### 1. Relational Data Layer & Analytics (SQL Server)
Converted longitudinal transactional medical records into targeted business views:
- **Operational Efficiency (`View_LengthOfStay`):** Length of stay per encounter across clinical encounter categories, reported two ways because hospitals use both: elapsed days, and midnights crossed, the census convention in which a same-day stay counts as zero. Inpatient stays average 4.75 days.
- **Clinical Sequences (`View_30DayReadmission`):** Applied a Common Table Expression (CTE) with chronological windowing (`LEAD`) to identify consecutive inpatient discharges and flag readmissions within a 30-day period. Synthea emits overlapping encounters, so the gap must fall between 0 and 30 days; a negative gap is an overlap, not a readmission. That rule removes 169 false readmissions, leaving 2,188 across 10,852 inpatient stays.
- **Population Risk Stratification (`View_PatientRiskStratification`):** Transformed diagnostic codes into patient-level metrics using **Conditional Aggregation** (`MAX(CASE WHEN...)`) to identify high-risk comorbidity groups (Type 2 Diabetes and Essential Hypertension). Conditions are identified by SNOMED CT code lists held in one table, `Ref_ConditionCodes`, so every view defines a condition the same way.
- **Cohort Alerts (`v_HighRiskCohortAlerts`):** Flags living patients with both type 2 diabetes and hypertension, or three or more encounters in the last 30 days of the extract. The window is measured from the extract's own last encounter date, because the extract is a snapshot: measured from today's date, the window drifts past the end of the data and the view returns nothing. Against a live feed, the as-of date becomes the current date.

### 2. Executive Dashboard (Power BI)
- Developed an automated **Operations Desk** to track patient volumes, average LOS trends, and seasonal inpatient capacity spikes.
- Established 1:N calendar dimensions to ensure robust time-series filtering across multiple EHR sources, preventing metric flattening.
  <img width="1802" height="1002" alt="image" src="https://github.com/user-attachments/assets/c716ef2a-f0a1-42be-be48-0f503825f610" />
  
### 3. Event-Driven Alerting Demo (Python -> Zapier -> LLM)

Two halves, deliberately separated so it is clear what this repository contains and what
is configured elsewhere.

**In this repository** (`python/Zapier EHR.py`): a Python script that assembles a nested
JSON clinical payload and POSTs it to a Zapier catch-hook endpoint using `urllib`. The
payload is **generated for demonstration** - it mirrors the shape of a high-risk cohort
record rather than being read from the SQL views above, so the script can be run without a
database. The endpoint is read from the `ZAPIER_WEBHOOK_URL` environment variable.

**Configured in Zapier, not in this repository:** the catch hook passes the payload to an
Gemini step driven by a system prompt I authored to force deterministic synthesis into a
three-bullet care-team briefing, which is then routed to a stakeholder channel. The
screenshots below show that output.
<img width="1772" height="137" alt="image" src="https://github.com/user-attachments/assets/7a75a8c2-b450-453c-8a51-052f47a8939e" />

<img width="16384" height="7603" alt="High-Risk Patient Alert - v2" src="https://github.com/user-attachments/assets/c372e433-1b6c-4992-915c-cf276676a464" />

<img width="742" height="516" alt="image" src="https://github.com/user-attachments/assets/be7b9194-0359-4118-9fc6-71e879488a82" />

## Corrections

Re-running the pipeline from this repository against the Synthea extract found four problems in the first published version. Each view has been re-verified against the full extract.

- **The setup script loaded no conditions or medications.** Their table definitions were one column short of Synthea's CSVs (`SYSTEM` and `PAYER`). `BULK INSERT` maps fields by position, so neither table loaded, and nothing downstream raised an error: every view that depends on them simply returned nothing. The tables now match the CSV headers, and the script ends with a load reconciliation so that an empty table is visible.
- **The risk stratification counted prediabetes as diabetes.** `DESCRIPTION LIKE '%Diabetes%'` flagged 4,967 patients, 3,332 of whom had prediabetes and no type 2 diabetes code at all. By code list the figure is 1,581.
- **The alert view had stopped returning anything.** Its hypertension code, `38341003`, does not occur in this extract - Synthea uses `59621000` - so the comorbidity branch never fired. Its 30-day window was measured from `GETDATE()`, which had moved past the end of the data. It now returns 994 patients.
- **`View_LengthOfStay` was not in the repository.** It had been created directly in the database, and the setup script, which rebuilds the database from scratch, removed it. It is now defined in `2.analytical_views.sql`.

Orphaned rows are also now moved to quarantine tables with a reason rather than deleted outright. On this extract there are none, but a load that discards clinical records should be able to show what it discarded.
