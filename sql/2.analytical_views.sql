/*
===============================================================================
Clinical Analytics Pipeline - Phase 2: Semantic Views & Analytics Modeling
Tech Stack: T-SQL / Window Functions / Conditional Aggregation
Author: Michelle Asinobi
===============================================================================
*/

USE ClinicalAnalytics;
GO

-- 1. OPERATIONAL & QUALITY METRIC: 30-DAY READMISSION TRACKING
CREATE OR ALTER VIEW View_30DayReadmission AS 
WITH TrackedStays AS (
    SELECT 
        Id AS CurrentEncounterID,
        PATIENT AS PatientId,
        [START] AS AdmissionDate,
        [STOP] AS DischargeDate, 
        ENCOUNTERCLASS AS CurrentClass,
        -- Fetch the next chronological admission date for this specific patient
        LEAD(START) OVER (PARTITION BY PATIENT ORDER BY START) AS NextAdmissionDate,
        -- Fetch the next chronological encounter class to confirm it's a hospitalization 
        LEAD(ENCOUNTERCLASS) OVER (PARTITION BY PATIENT ORDER BY START) AS NextClass
    FROM Encounters 
    WHERE ENCOUNTERCLASS = 'inpatient'
)
SELECT 
    CurrentEncounterId,
    PatientId,
    AdmissionDate,
    DischargeDate,
    NextAdmissionDate,
    NextClass,
    CASE 
        -- BETWEEN 0 AND 30, not <= 30. Synthea emits overlapping encounters, so the
        -- next admission can precede the current discharge; DATEDIFF is then negative,
        -- which also satisfies <= 30 and was being reported as a readmission.
        WHEN DATEDIFF(day, DischargeDate, NextAdmissionDate) BETWEEN 0 AND 30 THEN 'yes'
        ELSE 'no'
    END AS Is_30_Day_Readmission
FROM TrackedStays;
GO

-- 2. POPULATION HEALTH MANAGEMENT: LONGITUDINAL RISK STRATIFICATION
CREATE OR ALTER VIEW View_PatientRiskStratification AS 
WITH PatientFlags AS (
    SELECT 
        PATIENT AS PatientId,
        -- Collapse longitudinal vertical condition files into horizontal indicators
        MAX(CASE WHEN DESCRIPTION LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS Has_Diabetes,
        MAX(CASE WHEN DESCRIPTION LIKE '%Hypertension%' THEN 1 ELSE 0 END) AS Has_Hypertension,
        MAX(CASE WHEN DESCRIPTION LIKE '%Asthma%' THEN 1 ELSE 0 END) AS Has_Asthma
    FROM Conditions
    GROUP BY PATIENT
)
SELECT 
    PatientId,
    Has_Diabetes,
    Has_Hypertension,
    Has_Asthma,
    -- Evaluate the intersection of comorbidities for targeted population interventions
    CASE
        WHEN Has_Diabetes = 1 AND Has_Hypertension = 1 THEN 'High-Risk Comorbidity Cohort'
        ELSE 'Standard Care Cohort'
    END AS Clinical_Risk_Segment
FROM PatientFlags;
GO

-- 3. LIVE EVENT INTELLIGENCE: REAL-TIME AUTOMATED COHORT ALERTS
CREATE OR ALTER VIEW v_HighRiskCohortAlerts AS
-- Conditions and Encounters are aggregated to one row per patient BEFORE they meet
-- Patients. Joining both to Patients in a single query multiplies rows: a patient with
-- 2 conditions and 2 encounters yields 4, so COUNT(e.Id) reported 4 encounters where
-- there were 2, and the >= 3 alert threshold fired on patients who never reached it.
WITH ConditionFlags AS (
    SELECT
        PATIENT AS PatientId,
        MAX(CASE WHEN CODE = '44054006' THEN 1 ELSE 0 END) AS HasDiabetes, -- SNOMED: Type 2 Diabetes
        MAX(CASE WHEN CODE = '38341003' THEN 1 ELSE 0 END) AS HasHypertension -- SNOMED: Essential Hypertension
    FROM Conditions
    GROUP BY PATIENT
),
RecentEncounters AS (
    SELECT
        PATIENT AS PatientId,
        COUNT(DISTINCT Id) AS Total30DayEncounters
    FROM Encounters
    WHERE [START] >= DATEADD(day, -30, GETDATE())
    GROUP BY PATIENT
)
SELECT
    p.Id AS PatientID,
    p.FIRST + ' ' + p.LAST AS PatientName,
    DATEDIFF(year, p.BIRTHDATE, GETDATE()) AS CurrentAge,
    COALESCE(cf.HasDiabetes, 0) AS HasDiabetes,
    COALESCE(cf.HasHypertension, 0) AS HasHypertension,
    COALESCE(re.Total30DayEncounters, 0) AS Total30DayEncounters
FROM Patients p
-- LEFT, not INNER: the comorbidity branch below must still fire for a patient with no
-- encounter inside the 30-day window. An INNER JOIN silently excluded that whole cohort.
LEFT JOIN ConditionFlags cf ON p.Id = cf.PatientId
LEFT JOIN RecentEncounters re ON p.Id = re.PatientId
WHERE
    (COALESCE(cf.HasDiabetes, 0) = 1 AND COALESCE(cf.HasHypertension, 0) = 1)
    OR COALESCE(re.Total30DayEncounters, 0) >= 3;
GO