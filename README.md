# Automated Clinical Quality & Patient Outcome Data Pipeline

## Project Objective
Developed a comprehensive data analytics and workflow automation pipeline that ingests raw Electronic Health Record (EHR) transactions, models operational efficiency and patient safety metrics through a relational data layer, visualizes operational bottlenecks, and uses automated webhooks to deliver real-time AI care briefings for high-risk patient groups.

## Tech Stack & Ecosystem Architecture
- **Data Ingestion & Extraction (ETL):** Synthea Engine, SQL Server (SSMS), Bulk Insert operations.
- **Relational Modeling & Analytic Views:** T-SQL (Advanced CTEs, Window Functions `LEAD`, Conditional Aggregation `MAX(CASE)`).
- **Business Intelligence:** Power BI Desktop (DirectQuery Model, Time-Series DAX Relationships).
- **Workflow Automation & Intelligent Orchestration:** Zapier Pro, HTTP Webhooks, OpenAI API integration.

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
  
### 3. Event-Driven AI Automation (Zapier Pro & Python)
- Developed a lightweight automation simulation script in **Python** using `urllib` to process complex nested JSON data structures.
- Streamed live clinical payloads to a unique **Zapier Custom Webhook Endpoint** to simulate a modern connected Electronic Data Capture (EDC) system.
- Authored a contextual **System Prompt** forcing an LLM agent to execute deterministic data synthesis—generating immediate 3-bullet care team briefings for high-risk cohorts automatically routed to stakeholder channels.
<img width="1772" height="137" alt="image" src="https://github.com/user-attachments/assets/7a75a8c2-b450-453c-8a51-052f47a8939e" />

<img width="16384" height="7603" alt="High-Risk Patient Alert - v2" src="https://github.com/user-attachments/assets/c372e433-1b6c-4992-915c-cf276676a464" />

<img width="742" height="516" alt="image" src="https://github.com/user-attachments/assets/be7b9194-0359-4118-9fc6-71e879488a82" />


