/*
===============================================================================
Clinical Analytics Pipeline - Phase 1: Database Setup, Ingestion, & Cleaning
Tech Stack: T-SQL / SQL Server Management Studio (SSMS)
Author: Michelle Asinobi
===============================================================================

This script rebuilds the database from scratch. Anything created in
ClinicalAnalytics by hand - a view, a table, an index - is dropped by the next
run, so every object the pipeline depends on has to live in this repository.
*/

-- 1. DATABASE INITIALIZATION
USE master;
GO
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'ClinicalAnalytics')
BEGIN
    ALTER DATABASE ClinicalAnalytics SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ClinicalAnalytics;
END
GO
CREATE DATABASE ClinicalAnalytics;
GO
USE ClinicalAnalytics;
GO

-- 2. SCHEMA DEFINITION (CORE TABLES)
-- Column order matches the Synthea CSV headers exactly. BULK INSERT maps fields
-- by position, not by name, so a table one column short does not load.
CREATE TABLE Patients (
    Id VARCHAR(50) PRIMARY KEY,
    BIRTHDATE DATE,
    DEATHDATE DATE,
    SSN VARCHAR(20),
    DRIVERS VARCHAR(20),
    PASSPORT VARCHAR(20),
    PREFIX VARCHAR(20),
    FIRST VARCHAR(100),
    MIDDLE VARCHAR(100),
    LAST VARCHAR(100),
    SUFFIX VARCHAR(20),
    MAIDEN VARCHAR(100),
    MARITAL CHAR(1),
    RACE VARCHAR(50),
    ETHNICITY VARCHAR(50),
    GENDER CHAR(1),
    BIRTHPLACE VARCHAR(100),
    ADDRESS VARCHAR(255),
    CITY VARCHAR(100),
    STATE VARCHAR(100),
    COUNTY VARCHAR(100),
    FIPS VARCHAR(20),
    ZIP VARCHAR(20),
    LAT DECIMAL(9,6),
    LON DECIMAL(9,6),
    HEALTHCARE_EXPENSES DECIMAL(12,2),
    HEALTHCARE_COVERAGE DECIMAL(12,2),
    INCOME DECIMAL(12,2)
);

CREATE TABLE Encounters (
    Id VARCHAR(50) PRIMARY KEY,
    START DATETIME2,
    STOP DATETIME2,
    PATIENT VARCHAR(50),
    ORGANIZATION VARCHAR(50),
    PROVIDER VARCHAR(50),
    PAYER VARCHAR(50),
    ENCOUNTERCLASS VARCHAR(50),
    CODE VARCHAR(50),
    DESCRIPTION VARCHAR(1000),
    BASE_ENCOUNTER_COST DECIMAL(10,2),
    TOTAL_CLAIM_COST DECIMAL(10,2),
    PAYER_COVERAGE DECIMAL(10,2),
    REASONCODE VARCHAR(50),
    REASONDESCRIPTION VARCHAR(1000)
);

-- conditions.csv: START,STOP,PATIENT,ENCOUNTER,SYSTEM,CODE,DESCRIPTION
CREATE TABLE Conditions (
    START DATE,
    STOP DATE,
    PATIENT VARCHAR(50),
    ENCOUNTER VARCHAR(50),
    [SYSTEM] VARCHAR(100),     -- coding system URL; bracketed because SYSTEM is a keyword
    CODE VARCHAR(50),
    DESCRIPTION VARCHAR(1000)
);

-- medications.csv: START,STOP,PATIENT,PAYER,ENCOUNTER,CODE,DESCRIPTION,...
CREATE TABLE Medications (
    START DATETIME2,
    STOP DATETIME2,
    PATIENT VARCHAR(50),
    PAYER VARCHAR(50),
    ENCOUNTER VARCHAR(50),
    CODE VARCHAR(50),
    DESCRIPTION VARCHAR(1000),
    BASE_COST DECIMAL(10,2),
    PAYER_COVERAGE DECIMAL(10,2),
    DISPENSES INT,
    TOTALCOST DECIMAL(10,2),
    REASONCODE VARCHAR(50),
    REASONDESCRIPTION VARCHAR(1000)
);
GO

-- 3. BULK INGESTION OPERATIONS
-- Set @CsvPath to the folder holding Synthea's CSV output. It is the only
-- machine-specific value in the pipeline. BULK INSERT will not take a variable
-- as its file name, so the statements are assembled and executed together.
DECLARE @CsvPath NVARCHAR(400) = N'C:\Synthea\output\csv';

DECLARE @Options NVARCHAR(400) =
    N' WITH (FIRSTROW = 2, FORMAT = ''CSV'', FIELDQUOTE = ''"'', ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'', TABLOCK);';

DECLARE @Load NVARCHAR(MAX) =
      N'BULK INSERT Patients    FROM ''' + @CsvPath + N'\patients.csv'''    + @Options
    + N'BULK INSERT Encounters  FROM ''' + @CsvPath + N'\encounters.csv'''  + @Options
    + N'BULK INSERT Conditions  FROM ''' + @CsvPath + N'\conditions.csv'''  + @Options
    + N'BULK INSERT Medications FROM ''' + @CsvPath + N'\medications.csv''' + @Options;

EXEC sp_executesql @Load;
GO

-- 4. PIPELINE QUALITY CONTROL: QUARANTINE, NOT DELETE
-- Rows that reference an encounter missing from the extract are moved to a
-- quarantine table with a reason and a timestamp before they are removed from
-- the analytic tables. Received clinical data is not discarded silently: ALCOA+
-- requires the original record to stay intact and attributable, and a bare
-- DELETE leaves no trace of what was removed or why.
SELECT c.*,
       CAST('Condition references an encounter not in the extract' AS VARCHAR(200)) AS QuarantineReason,
       SYSUTCDATETIME() AS QuarantinedAt
INTO Quarantine_Conditions
FROM Conditions c
WHERE NOT EXISTS (SELECT 1 FROM Encounters e WHERE e.Id = c.ENCOUNTER);

DELETE c FROM Conditions c
WHERE NOT EXISTS (SELECT 1 FROM Encounters e WHERE e.Id = c.ENCOUNTER);
GO

SELECT m.*,
       CAST('Medication references an encounter not in the extract' AS VARCHAR(200)) AS QuarantineReason,
       SYSUTCDATETIME() AS QuarantinedAt
INTO Quarantine_Medications
FROM Medications m
WHERE NOT EXISTS (SELECT 1 FROM Encounters e WHERE e.Id = m.ENCOUNTER);

DELETE m FROM Medications m
WHERE NOT EXISTS (SELECT 1 FROM Encounters e WHERE e.Id = m.ENCOUNTER);
GO

-- 5. RELATIONAL INTEGRITY ENFORCEMENT (FOREIGN KEYS)
ALTER TABLE Encounters
ADD CONSTRAINT FK_Encounters_Patients FOREIGN KEY (PATIENT) REFERENCES Patients(Id);
GO

ALTER TABLE Conditions
ADD CONSTRAINT FK_Conditions_Patients FOREIGN KEY (PATIENT) REFERENCES Patients(Id);
GO

ALTER TABLE Conditions
ADD CONSTRAINT FK_Conditions_Encounters FOREIGN KEY (ENCOUNTER) REFERENCES Encounters(Id);
GO

ALTER TABLE Medications
ADD CONSTRAINT FK_Medications_Patients FOREIGN KEY (PATIENT) REFERENCES Patients(Id);
GO

ALTER TABLE Medications
ADD CONSTRAINT FK_Medications_Encounters FOREIGN KEY (ENCOUNTER) REFERENCES Encounters(Id);
GO

-- 6. LOAD RECONCILIATION
-- A load that silently fails leaves an empty table and a pipeline that still
-- runs, which is what happened to Conditions and Medications before their
-- column lists matched the CSVs. Nothing downstream errors; every view that
-- depends on them just returns nothing. Check these counts after every run.
--
-- Expected on the 11,482-patient Synthea extract:
--   Patients 11,482 | Encounters 678,233 | Conditions 420,855 | Medications 591,811
--   Quarantine_Conditions 0 | Quarantine_Medications 0
SELECT 'Patients' AS TableName, COUNT(*) AS LoadedRows FROM Patients
UNION ALL SELECT 'Encounters',             COUNT(*) FROM Encounters
UNION ALL SELECT 'Conditions',             COUNT(*) FROM Conditions
UNION ALL SELECT 'Medications',            COUNT(*) FROM Medications
UNION ALL SELECT 'Quarantine_Conditions',  COUNT(*) FROM Quarantine_Conditions
UNION ALL SELECT 'Quarantine_Medications', COUNT(*) FROM Quarantine_Medications;
GO
