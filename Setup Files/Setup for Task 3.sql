CREATE TABLE Device_Status
(
    Device_ID      VARCHAR(10) ,
    Device_Type    VARCHAR(50) ,
    Location       VARCHAR(50) ,
    Status         VARCHAR(30) ,
    Schedule_Date  DATE         
);


INSERT INTO Device_Status (Device_ID, Device_Type, Location, Status, Schedule_Date)
VALUES
('D101', 'Ventilator', 'ICU',       'Active',      '2026-03-27'),
('D102', 'MRI',        'Radiology', 'Active',      '2026-03-27'),
('D103', 'Pump',       'ER',        'Maintenance', '2026-03-27');


CREATE TABLE Device_Status_Target    
(
    Device_Key    INT IDENTITY(1,1) PRIMARY KEY,
    Device_ID     VARCHAR(10)  ,
    Device_Type   VARCHAR(50)  ,
    Location      VARCHAR(50)  ,
    Status        VARCHAR(30)  ,
    Insert_Date   DATE          ,
    Active_Flag   INT           ,
    Version_No    INT           
);

select * from Device_Status;
select * from Device_Status_Target;

SELECT * 
FROM dbo.Device_Status_Target
ORDER BY Device_Key;


UPDATE dbo.Device_Status
SET Schedule_Date = '2026-03-28'
WHERE Device_ID = 'D101';


drop table Device_Status;
drop table Device_Status_Target;