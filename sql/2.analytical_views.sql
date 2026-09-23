/*
===============================================================================
Clinical Analytics Pipeline - Phase 2: Semantic Views & Analytics Modeling
Tech Stack: T-SQL / Window Functions / Conditional Aggregation
Author: Michelle Asinobi
===============================================================================
*/

USE ClinicalAnalytics;
GO

-- 0. CLINICAL CODE LISTS
-- One definition of each condition, shared by every view that needs it.
-- Descriptions were used to build and audit these lists; the codes apply them.
-- Matching on description text instead is unreliable in both directions:
-- LIKE '%Diabetes%' counts prediabetes as diabetes (3,332 patients in this
-- extract, two thirds of everyone it flags), while a single base code misses
-- the patients whose diabetes is recorded only under a complication (733).
DROP TABLE IF EXISTS Ref_ConditionCodes;
CREATE TABLE Ref_ConditionCodes (
    Concept VARCHAR(30),
    CODE VARCHAR(50),
    DESCRIPTION VARCHAR(200),
    PRIMARY KEY (Concept, CODE)
);
INSERT INTO Ref_ConditionCodes VALUES
    ('Type 2 diabetes', '44054006',        'Diabetes mellitus type 2 (disorder)'),
    ('Type 2 diabetes', '368581000119106', 'Neuropathy due to type 2 diabetes mellitus (disorder)'),
    ('Type 2 diabetes', '1551000119108',   'Nonproliferative diabetic retinopathy due to type II diabetes mellitus'),
    ('Type 2 diabetes', '1501000119109',   'Proliferative diabetic retinopathy due to type II diabetes mellitus'),
    ('Type 2 diabetes', '97331000119101',  'Macular edema and retinopathy due to type 2 diabetes mellitus (disorder)'),
    ('Type 2 diabetes', '90781000119102',  'Microalbuminuria due to type 2 diabetes mellitus (disorder)'),
    ('Type 2 diabetes', '157141000119108', 'Proteinuria due to type 2 diabetes mellitus (disorder)'),
    ('Type 2 diabetes', '60951000119105',  'Blindness due to type 2 diabetes mellitus (disorder)'),
    -- Synthea codes essential hypertension as 59621000. The broader parent
    -- concept 38341003 does not occur in this extract but other sources use it.
    ('Hypertension',    '59621000',        'Essential hypertension (disorder)'),
    ('Hypertension',    '38341003',        'Hypertensive disorder, systemic arterial (disorder)'),
    ('Asthma',          '195967001',       'Asthma (disorder)'),
    ('Asthma',          '233678006',       'Childhood asthma (disorder)');
-- Not listed, deliberately: 714628002 Prediabetes, and 127013003 Disorder of
-- kidney due to diabetes mellitus, which does not state the diabetes type.
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
        -- Always 'inpatient' or NULL: the WHERE clause below runs before the
        -- window function, so LEAD only ever sees inpatient stays. Kept so the
        -- view's columns do not change.
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
        c.PATIENT AS PatientId,
        -- Collapse longitudinal vertical condition files into horizontal indicators
        MAX(CASE WHEN r.Concept = 'Type 2 diabetes' THEN 1 ELSE 0 END) AS Has_Diabetes,
        MAX(CASE WHEN r.Concept = 'Hypertension'    THEN 1 ELSE 0 END) AS Has_Hypertension,
        MAX(CASE WHEN r.Concept = 'Asthma'          THEN 1 ELSE 0 END) AS Has_Asthma
    FROM Conditions c
    LEFT JOIN Ref_ConditionCodes r ON r.CODE = c.CODE
    GROUP BY c.PATIENT
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

-- 3. LIVE EVENT INTELLIGENCE: AUTOMATED COHORT ALERTS
CREATE OR ALTER VIEW v_HighRiskCohortAlerts AS
-- The extract is a snapshot, so "the last 30 days" means the last 30 days of
-- the extract, not of the calendar. Measured from GETDATE() the window drifted
-- past the end of the data within a month of it being generated, and the view
-- has returned nothing since. Against a live feed, AsOf becomes GETDATE().
WITH AsOf AS (
    SELECT CAST(MAX([START]) AS DATE) AS AsOfDate FROM Encounters
),
-- Conditions and Encounters are aggregated to one row per patient BEFORE they meet
-- Patients. Joining both to Patients in a single query multiplies rows: a patient with
-- 2 conditions and 2 encounters yields 4, so COUNT(e.Id) reported 4 encounters where
-- there were 2, and the >= 3 alert threshold fired on patients who never reached it.
ConditionFlags AS (
    SELECT
        c.PATIENT AS PatientId,
        MAX(CASE WHEN r.Concept = 'Type 2 diabetes' THEN 1 ELSE 0 END) AS HasDiabetes,
        MAX(CASE WHEN r.Concept = 'Hypertension'    THEN 1 ELSE 0 END) AS HasHypertension
    FROM Conditions c
    JOIN Ref_ConditionCodes r ON r.CODE = c.CODE
    GROUP BY c.PATIENT
),
RecentEncounters AS (
    SELECT
        e.PATIENT AS PatientId,
        COUNT(DISTINCT e.Id) AS Total30DayEncounters
    FROM Encounters e
    CROSS JOIN AsOf a
    WHERE e.[START] >= DATEADD(day, -30, a.AsOfDate)
      AND e.[START] <  DATEADD(day, 1, a.AsOfDate)
    GROUP BY e.PATIENT
)
SELECT
    p.Id AS PatientID,
    p.FIRST + ' ' + p.LAST AS PatientName,
    a.AsOfDate,
    -- Whole years at the as-of date. DATEDIFF(year, ...) alone counts calendar
    -- year boundaries and overstates age by one before each birthday.
    DATEDIFF(year, p.BIRTHDATE, a.AsOfDate)
      - CASE WHEN DATEADD(year, DATEDIFF(year, p.BIRTHDATE, a.AsOfDate), p.BIRTHDATE) > a.AsOfDate
             THEN 1 ELSE 0 END AS AgeAtAsOf,
    COALESCE(cf.HasDiabetes, 0) AS HasDiabetes,
    COALESCE(cf.HasHypertension, 0) AS HasHypertension,
    COALESCE(re.Total30DayEncounters, 0) AS Total30DayEncounters
FROM Patients p
CROSS JOIN AsOf a
-- LEFT, not INNER: the comorbidity branch below must still fire for a patient with no
-- encounter inside the 30-day window. An INNER JOIN silently excluded that whole cohort.
LEFT JOIN ConditionFlags cf ON p.Id = cf.PatientId
LEFT JOIN RecentEncounters re ON p.Id = re.PatientId
WHERE
    -- A care-team alert about a patient who has died is not an alert.
    (p.DEATHDATE IS NULL OR p.DEATHDATE > a.AsOfDate)
    AND (
        (COALESCE(cf.HasDiabetes, 0) = 1 AND COALESCE(cf.HasHypertension, 0) = 1)
        OR COALESCE(re.Total30DayEncounters, 0) >= 3
    );
GO

-- 4. OPERATIONAL EFFICIENCY: LENGTH OF STAY
CREATE OR ALTER VIEW View_LengthOfStay AS
-- One row per encounter, so length of stay can be averaged or sliced by
-- encounter class in the report. Two measures, because hospitals report two:
--   LengthOfStayDays  elapsed time, in days to two decimal places
--   MidnightsCrossed  the census convention - a same-day stay counts as 0
-- Encounters with no discharge time, or one before admission, have no
-- measurable stay and are left out. There are none in this extract.
SELECT
    Id AS EncounterId,
    PATIENT AS PatientId,
    ENCOUNTERCLASS AS EncounterClass,
    [START] AS AdmissionDate,
    [STOP] AS DischargeDate,
    CAST(DATEDIFF(minute, [START], [STOP]) / 1440.0 AS DECIMAL(9,2)) AS LengthOfStayDays,
    DATEDIFF(day, [START], [STOP]) AS MidnightsCrossed
FROM Encounters
WHERE [STOP] IS NOT NULL
  AND [STOP] >= [START];
GO
