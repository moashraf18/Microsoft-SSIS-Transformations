SELECT * from air_quality_Q1;


      CREATE TABLE air_quality_Q1 (
        sensor_id VARCHAR(50),
        city VARCHAR(50),
        timestamp DATETIME,
        pm25 int,
        pm10 int,
        source VARCHAR(10)
    );

    drop table air_Quality_Q1;