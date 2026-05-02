CREATE TABLE DimCampaign
(
    CampaignSK    INT IDENTITY(1,1) PRIMARY KEY,
    ID            INT NOT NULL,
    Name          NVARCHAR(100),
    Budget        DECIMAL(18,2),
    CurrentName   NVARCHAR(100),
    CurrentBudget DECIMAL(18,2),
    PrevName      NVARCHAR(100),
    PrevBudget    DECIMAL(18,2),
    StartDate     DATETIME,
    EndDate       DATETIME,
    IsCurrent     BIT
);



CREATE TABLE Campaign_Q2 (
    ID          INT PRIMARY KEY,
    Name        NVARCHAR(100),
    Budget      DECIMAL(18,2),
    Update_Date DATETIME
);

INSERT INTO Campaign_Q2 VALUES
(1001, 'Summer Ads', 10000, '2026-01-01'),
(1002, 'Winter Ads', 15000, '2026-01-01'),
(1003, 'Spring Ads', 20000, '2026-01-01');



CREATE TABLE ETL_Metadata
(
    ProcessName VARCHAR(100) PRIMARY KEY,
    LastLoadDate DATETIME
);

INSERT INTO ETL_Metadata VALUES
('Campaign_SCD6','1900-01-01');

--------------------------------------------------------------------------------------

--Testing:
DELETE FROM Campaign_Q2;

INSERT INTO Campaign_Q2 VALUES
(1001, 'Summer Ads', 10000, '2026-01-01 00:00:00'),
(1002, 'Winter Ads', 15000, '2026-01-01 00:00:00'),
(1003, 'Spring Ads', 20000, '2026-01-01 00:00:00');

TRUNCATE TABLE DimCampaign;

UPDATE ETL_Metadata
SET LastLoadDate = '1900-01-01'
WHERE ProcessName = 'Campaign_SCD6';

-- Run the package

SELECT *
FROM DimCampaign
ORDER BY ID; -- You should Find 3 Rows --> IsCurrent = 1

INSERT INTO Campaign_Q2
VALUES (1004, 'Autumn Ads', 30000, GETDATE());

-- Run the package

SELECT *
FROM DimCampaign
WHERE ID = 1004; -- You should Find a new Row with Id = 1004

UPDATE Campaign_Q2
SET Budget = 25000,
    Update_Date = GETDATE()
WHERE ID = 1003;

-- Run the package

SELECT *
FROM DimCampaign
WHERE ID = 1003
ORDER BY CampaignSK; -- You should Find 2 Rows for Id = 1003
/*
| ID   | CurrentBudget | PrevBudget | IsCurrent |
| ---- | ------------- | ---------- | --------- |
| 1003 | 20000         | NULL       | 0         |
| 1003 | 25000         | 20000      | 1         |
*/