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
        WHEN DATEDIFF(day, DischargeDate, NextAdmissionDate) <= 30 THEN 'yes'
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
SELECT 
    p.Id AS PatientID,
    p.FIRST + ' ' + p.LAST AS PatientName,
    DATEDIFF(year, p.BIRTHDATE, GETDATE()) AS CurrentAge,
    MAX(CASE WHEN c.CODE = '44054006' THEN 1 ELSE 0 END) AS HasDiabetes, -- SNOMED: Type 2 Diabetes
    MAX(CASE WHEN c.CODE = '38341003' THEN 1 ELSE 0 END) AS HasHypertension, -- SNOMED: Essential Hypertension
    COUNT(e.Id) AS Total30DayEncounters
FROM Patients p
INNER JOIN Conditions c ON p.Id = c.PATIENT
INNER JOIN Encounters e ON p.Id = e.PATIENT
WHERE e.START >= DATEADD(day, -30, GETDATE())
GROUP BY p.Id, p.FIRST, p.LAST, p.BIRTHDATE
HAVING 
    (MAX(CASE WHEN c.CODE = '44054006' THEN 1 ELSE 0 END) = 1 
     AND MAX(CASE WHEN c.CODE = '38341003' THEN 1 ELSE 0 END) = 1)
    OR COUNT(e.Id) >= 3;
GO