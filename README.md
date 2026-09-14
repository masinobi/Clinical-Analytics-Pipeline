# Automated Clinical Quality & Patient Outcome Data Pipeline

## Project Objective
An end-to-end clinical analytics build on **synthetic patient records generated with
[Synthea](https://github.com/synthetichealth/synthea)**. Raw EHR extracts are loaded into SQL
Server, modelled into operational-efficiency and patient-safety views, visualised in Power BI,
and used as the basis for an event-driven alerting demo that produces care-team briefings for
high-risk cohorts.

> **No real patient data appears anywhere in this repository.** Every record is synthetic.

## Tech Stack & Ecosystem Architecture
- **Data Ingestion & Extraction (ETL):** Synthea Engine, SQL Server (SSMS), Bulk Insert operations.
- **Relational Modeling & Analytic Views:** T-SQL (Advanced CTEs, Window Functions `LEAD`, Conditional Aggregation `MAX(CASE)`).
- **Business Intelligence:** Power BI Desktop (DirectQuery Model, Time-Series DAX Relationships).
- **Workflow Automation & Intelligent Orchestration:** Zapier Pro, HTTP Webhooks, Google Gemini API. *The LLM step and channel routing live inside Zapier and are not part of this repository - see section 3.*

## Key Pipeline Deliverables & Engineering Milestones

### 1. Relational Data Layer & Analytics (SQL Server)
Converted longitudinal transactional medical records into targeted business views:
- **Operational Efficiency:** Assessed Length of Stay (LOS) by calculating duration across clinical encounter categories.
- **Clinical Sequences (30-Day Readmissions):** Applied a Common Table Expression (CTE) with chronological windowing (`LEAD`) to identify consecutive inpatient discharges and flag readmissions within a 30-day period.
- **Population Risk Stratification:** Transformed diagnostic codes into patient-level metrics using **Conditional Aggregation** (`MAX(CASE WHEN...)`) to identify high-risk comorbidity groups (Type 2 Diabetes and Essential Hypertension).

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


