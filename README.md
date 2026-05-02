# Microsoft SSIS Transformations — Air Quality & Trading Data Warehouse

> **A Data Warehousing Assignment** by Mohamed Ashraf  
> Built with SQL Server Integration Services (SSIS) 17 · SQL Server · .NET Framework 4.7  
> Database: `DW_Assignment` on server `MSI`

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [What is SSIS and Why Do We Use It?](#2-what-is-ssis-and-why-do-we-use-it)
3. [Repository Structure](#3-repository-structure)
4. [Package-by-Package Explanation](#4-package-by-package-explanation)
   - [Task 1 — Multi-Source Air Quality Ingestion](#task-1--multi-source-air-quality-ingestion)
   - [Task 2 — SCD Type 6 Campaign Dimension](#task-2--scd-type-6-campaign-dimension)
   - [Task 3 — Device Status Snapshot (Versioned Load)](#task-3--device-status-snapshot-versioned-load)
   - [Task 4 — Trader Summary Fact Table](#task-4--trader-summary-fact-table)
5. [SSIS Transformations Used — Deep Dive](#5-ssis-transformations-used--deep-dive)
6. [Connections & Prerequisites](#6-connections--prerequisites)
7. [How to Run](#7-how-to-run)

---

## 1. Project Overview

This project demonstrates a complete Data Warehousing ETL pipeline built with Microsoft SSIS. It ingests data from three different source types (CSV flat files, XML files, and a live REST API), cleans and validates the data, implements a Slowly Changing Dimension, loads versioned snapshots, and builds a fact table from raw trading transactions — all into the `DW_Assignment` SQL Server database.

The four SSIS packages together cover the full spectrum of real-world DW engineering challenges: multi-source integration, data quality enforcement, SCD management, incremental loading, and analytical aggregation.

---

## 2. What is SSIS and Why Do We Use It?

**SQL Server Integration Services (SSIS)** is Microsoft's enterprise ETL (Extract, Transform, Load) platform. It is the engine that moves data from the messy, heterogeneous world of operational systems into the clean, structured world of a data warehouse.

### The Core Problem SSIS Solves

Your organization's data lives in many places — CSV exports from sensors, XML feeds from partner systems, REST APIs, legacy databases. Each has a different format, different data types, different encoding (notice `CodePage=1256` for Arabic text throughout these packages), and different quality levels. The data warehouse needs **one version of truth**. SSIS is the plumbing that makes that happen.

### Why Not Just Write SQL?

SQL operates on data that is **already in the database**. SSIS operates on data **in transit** — it can pull from any source, apply complex row-by-row business logic, validate and cleanse mid-stream, and load to any destination, all without writing the data to a temporary table first. It processes data in memory buffers, making it extremely fast for large volumes.

### The SSIS Architecture

Every SSIS package has two layers:

- **Control Flow**: The orchestration layer. Tasks run sequentially or in parallel (Execute SQL Task, Data Flow Task, etc.). Think of it as the "when and in what order" layer.
- **Data Flow Task (DFT)**: The transformation engine. Data flows through a pipeline of components in memory. Think of it as the "what happens to each row" layer.

---

## 3. Repository Structure

```
Microsoft-SSIS-Transformations/
│
├── Setup Files/
│   ├── Air_Quality.csv          # Flat file source — sensor readings
│   ├── Air_Quality.xml          # XML source — monitoring stations
│   ├── Air_Quality.xsd          # XML schema definition
│   └── [SQL scripts]            # Database/table creation scripts
│
└── The Project/
    ├── Task_1.dtsx              # Multi-source air quality ingestion
    ├── Task_2.dtsx              # SCD Type 6 campaign dimension
    ├── Task_3.dtsx              # Device status versioned snapshot
    └── Task_4.dtsx              # Trader summary fact table
```

---

## 4. Package-by-Package Explanation

---

### Task 1 — Multi-Source Air Quality Ingestion

**Target Table**: `dbo.air_quality_Q1`

**The Business Problem**: Air quality readings arrive from three completely different systems — a CSV file from local sensors, an XML file from partner monitoring stations, and a live REST API for US air quality data. All three must be cleaned, tagged with their source, and loaded into a single unified staging table.

**Control Flow**: Three Data Flow Tasks run sequentially:  
`DFT_CSV` → `DFT_XML` → `DFT_API`

This ordering is enforced by **Precedence Constraints**, ensuring the CSV loads first, then XML, then the API — so if any task fails, downstream tasks don't run on incomplete data.

#### DFT_CSV — CSV Source Pipeline

```
Flat File Source → Data Conversion → Conditional Split → Conditional Split 1 → Adding_SRC_Col → Data Conversion 1 → OLE DB Destination
                                          ↓ (No city)
                                       [Discarded]
                                                              ↓ (wrong pollution rate: pm25<0 or pm10<0)
                                                           [Discarded]
```

The CSV file (`Air_Quality.csv`) contains columns: `sensor_id`, `city`, `measurement_time`, `pm_25`, `pm_10`, `unit`.

Because CSV files come in as plain text, **all columns arrive as strings (DataType 129/str)**. The pipeline must:

1. **Data Conversion** — Convert `pm_25` and `pm_10` from `str` to `numeric(18)` so arithmetic comparisons are possible.
2. **Conditional Split** — Check `ISNULL(city) || TRIM(city) == ""` → rows with no city are invalid and discarded.
3. **Conditional Split 1** — Check `[Copy of pm_25] < 0 || [Copy of pm_10] < 0` → negative pollution readings are physically impossible and discarded.
4. **Adding_SRC_Col (Derived Column)** — Adds a new column `Source = "CSV"` so analysts can always trace which system a record came from.
5. **Data Conversion 1** — Converts `measurement_time` from `str` to `dbTimeStamp`, and `Source` from Unicode `wstr` to ANSI `str` (CodePage 1256) to match the destination table's column type.

#### DFT_XML — XML Source Pipeline

```
XML Source → Adding_SRC_Column → Data Conversion → Conditional Split → OLE DB Destination
                                                          ↓ (Invalid: null city or negative PM)
                                                       [Discarded]
```

The XML file contains: `StationID`, `City`, `Time`, `PM25`, `PM10`.

The **XML Source** adapter reads the file using an `.xsd` schema definition and outputs typed columns. `PM25` arrives as `i2` (16-bit integer) and `PM10` as `ui2` (unsigned 16-bit). These need to be promoted to `numeric(18)` via **Data Conversion** before the validation split can compare them. A `Source = "XML"` tag is stamped via **Derived Column**.

#### DFT_API — REST API Source Pipeline

```
Script Component (C# — calls REST API) → Adding_SRC_Column → Data Conversion → Conditional Split → OLE DB Destination
                                                                                      ↓ (Invalid)
                                                                                   [Discarded]
```

This is the most sophisticated source. The **Script Component** contains embedded C# code that:
- Makes an HTTPS call to `https://69be08c917c3d7d977910f4e.mockapi.io/us_air_quality/air_monitoring`
- Uses `Newtonsoft.Json` (NuGet package included in the binary) to parse the JSON response
- Iterates the JSON array and populates the output buffer with `id`, `location`, `timestamp`, `pm25`, `pm10`

This is the pattern you use when SSIS's built-in sources cannot handle the data format — write a Script Component as a custom source.

---

### Task 2 — SCD Type 6 Campaign Dimension

**Source Table**: `dbo.Campaign_Q2`  
**Target Table**: `dbo.DimCampaign`

**The Business Problem**: Campaign data changes over time — campaigns get renamed, budgets get revised. In a data warehouse, you must track *all historical versions* of a dimension record, not just the current one. This is called a **Slowly Changing Dimension (SCD)**. This package implements **SCD Type 6** (also called a "hybrid SCD"), which combines Type 1 (overwrite current values), Type 2 (insert new historical row), and Type 3 (keep previous values) in a single row design.

The `DimCampaign` table has this structure:

| Column | Purpose |
|--------|---------|
| `CampaignSK` | Surrogate key (auto-generated) |
| `ID` | Natural/business key |
| `Name` / `Budget` | Current source values |
| `CurrentName` / `CurrentBudget` | Type 1: always reflects latest value |
| `PrevName` / `PrevBudget` | Type 3: the value before the last change |
| `StartDate` / `EndDate` | Type 2: the validity period of this row |
| `IsCurrent` | Flag: 1 = active row, 0 = expired |

**Control Flow**:

```
Execute SQL Task (get LastLoadDate) → Data Flow Task → Execute SQL Task (update metadata)
```

The **Execute SQL Task** at the start reads the last successful load date from an `ETL_Metadata` table into a package variable `User::LastLoadDate`. The OLE DB Source then uses this variable to filter: `WHERE CAST(Update_Date AS DATETIME) > ?` — this is **incremental loading**, only processing rows that changed since the last run.

#### Data Flow — The SCD6 Logic

```
OLE DB Source → Lookup (DimCampaign WHERE IsCurrent=1)
                    ↓ No Match (new campaign)        ↓ Match (existing campaign)
              New Rows Path                    Conditional Split
              (Derived Column)               (Name != Lookup_Name OR Budget != Lookup_Budget?)
                    ↓                          ↓ Changed              ↓ Not Changed
              Union All ←──────── Multicast ──→ Expire Old Row        (discarded)
                                      ↓         (UPDATE: EndDate=NOW, IsCurrent=0)
                                 Update Historical Current Values
                                      (UPDATE: CurrentName, CurrentBudget)
                                      ↓
                                 Prepare New Version Row
                                 (Derived Column: new row with PrevName=old CurrentName)
                                      ↓
                                 Union All → OLE DB Destination
```

**The Lookup Transformation** is the heart of SCD processing. It joins incoming source rows against the current dimension snapshot (`WHERE IsCurrent=1`) on the business key (`ID`). Rows that match are existing campaigns; rows that don't match are new campaigns.

**The Multicast Transformation** fans out changed rows to three simultaneous paths — this is critical because a single changed row requires three operations: expire the old row, update the current-values columns on ALL historical rows for that campaign, and insert a brand new version row.

**The OLE DB Command Transformation** runs a parameterized SQL `UPDATE` statement for each row passing through it — this is used for the `Expire Old Row` and `Update Historical Current Values` operations. It is more expensive than bulk-insert but necessary when you need row-level UPDATE logic.

**The Union All Transformation** recombines the two insert paths (new campaigns + new versions of changed campaigns) into a single stream for the destination.

---

### Task 3 — Device Status Snapshot (Versioned Load)

**Source Table**: `dbo.Device_Status` (on a separate `DESKTOP-20C4V96.data_warehouse` server)  
**Target Table**: `dbo.Device_Status_Target` (on `MSI.DW_Assignment`)

**The Business Problem**: IoT device status snapshots are taken periodically. Each snapshot is a complete picture of all devices at a point in time. The target table needs to track every snapshot as a separate version, with the most recent snapshot flagged as active.

**Control Flow** (4 steps in sequence):

```
GET_Run_Date → GET_VersionNo → Set_Old_Active_Rows → DFT_Q3
```

1. **GET_Run_Date** (Execute SQL Task): Queries `MAX(Schedule_Date)` from the source and stores it in `User::RunDate`. This tells the package what date this snapshot represents.

2. **GET_VersionNo** (Execute SQL Task): Queries the target table for the max existing `Version_No` for that `RunDate` and adds 1. Stored in `User::VersionNo`. This ensures each load of the same date gets an incrementing version number.

3. **Set_Old_Active_Rows** (Execute SQL Task): Runs `UPDATE Device_Status_Target SET Active_Flag = 0 WHERE Active_Flag = 1`. This deactivates all previously active rows before loading the new snapshot — a classic "expire and replace" pattern.

4. **DFT_Q3** (Data Flow Task): Loads the new snapshot.

```
OLE DB Source (Device_Status) → ADD_COLUMNS (Derived Column) → OLE DB Destination
```

The **ADD_COLUMNS Derived Column** stamps three metadata columns onto every row:
- `Insert_Date = (DT_DBDATE)@[User::RunDate]` — the snapshot date
- `Active_Flag = (DT_I4)1` — marks this batch as the current active snapshot
- `Version_No = (DT_I4)@[User::VersionNo]` — the incremented version counter

This is a textbook **Derived Column** use case: enriching rows with metadata that doesn't exist in the source system but is required by the warehouse schema.

---

### Task 4 — Trader Summary Fact Table

**Source Table**: `dbo.raw_trades`  
**Target Table**: `dbo.Trader_Summary`

**The Business Problem**: Raw trading data contains individual buy/sell transactions with possible data quality issues (negative quantities mean sell recorded as negative, duplicate timestamps). The goal is to produce a clean daily summary per trader showing total quantities bought and total quantities sold.

**Data Flow** — the most complex of the four packages:

```
OLE DB Source (raw_trades) 
    → Derived Column (normalize Action & Quantity)
    → Script Component (deduplicate & enforce buy/sell logic)
    → Conditional Split (filter zero-quantity rows)
    → Data Conversion (timestamp → date)
    → Conditional Split 1 (split buy vs sell streams)
        ↓ Action="buy"                    ↓ Action≠"buy" (sell)
    Aggregate (SUM quantityOut)      Aggregate 1 (SUM quantityOut)
    Sort (by Trader ID)              Sort 1 (by Trader ID)
        ↓                                 ↓
    Merge Join (FULL OUTER JOIN on Trader ID + Date)
    → Derived Column 1 (handle NULLs from outer join, create final columns)
    → OLE DB Destination (Trader_Summary)
```

#### Step-by-Step Logic

**Derived Column (data normalization)**: Some records have negative `Quantity` values, meaning the system recorded a sell as a negative buy. The expression `Quantity > 0 ? Quantity : Quantity * -1` makes all quantities positive. Simultaneously, the `Action` column is corrected: if `Quantity` was negative and the action said "buy", it's flipped to "sell" (and vice versa).

**Script Component (C# business rule deduplication)**: This is a stateful transformation — it maintains state across rows. The logic:
- Tracks the previous trader ID and timestamp
- If the same trader has the same timestamp as the previous row, skip it (duplicate)
- Tracks the maximum buy quantity seen so far per trader
- If a sell quantity exceeds the trader's maximum buy, the sell is invalid (you can't sell more than you've ever bought) — that row is filtered out

**Aggregate Transformation**: Groups by `(Trader_ID, Date)` and computes `SUM(quantityOut)`. One Aggregate node handles only "buy" rows; another handles only "sell" rows. This produces two separate streams: one with total buying volume per trader per day, one with total selling volume.

**Sort Transformation**: The Merge Join requires both input streams to be **sorted on the join key**. The Sort transformation sorts each aggregate output by `Trader_ID`.

**Merge Join (FULL OUTER JOIN)**: Joins the buy-summary stream with the sell-summary stream on `Trader_ID + Date`. A FULL OUTER JOIN is used because a trader might have bought but not sold on a given day (or vice versa) — an INNER JOIN would silently drop those traders.

**Derived Column 1 (NULL handling)**: Since it's a full outer join, either side can be NULL. The expressions `ISNULL(Buying) ? 0 : Buying` and `ISNULL(Selling) ? 0 : Selling` replace NULLs with zeros. `Trader_ID_summary` is resolved with `ISNULL(id) ? [id (1)] : id` — using whichever side of the join is not null.

---

## 5. SSIS Transformations Used — Deep Dive

### Flat File Source
**What it does**: Reads delimited or fixed-width text files (CSV, TSV, etc.).  
**Why we use it**: Most operational systems can export CSV. The connection manager defines the delimiter (`,`), encoding (CodePage 1256 for Arabic locale), and column structure. Columns arrive as strings regardless of their logical type — that's why Data Conversion always follows.

### XML Source
**What it does**: Reads XML files and maps elements to output columns using an XSD schema.  
**Why we use it**: Partner systems often exchange data in XML. The XSD is required to tell SSIS how to navigate the XML hierarchy and what types to assign to each element.

### Script Component (as Source)
**What it does**: Executes arbitrary C# or VB.NET code that populates an output buffer.  
**Why we use it**: When no built-in source can handle your data format — REST APIs, FTP downloads, custom file formats, web scraping. The Task 1 API package downloads a JSON array from a mockAPI endpoint, parses it with Newtonsoft.Json, and pushes rows into the SSIS pipeline programmatically.

### Script Component (as Transformation)
**What it does**: Processes each row with custom C# code, can read and write column values.  
**Why we use it**: When business rules are too complex for SSIS expressions. Task 4 uses it to maintain stateful deduplication logic across rows — tracking the previous trader's ID and timestamp, and enforcing the rule that a sell cannot exceed the maximum historical buy quantity.

### Data Conversion
**What it does**: Converts a column from one data type to another, producing a new "Copy of X" column alongside the original.  
**Why we use it**: Sources often deliver data in the wrong type. CSV files deliver everything as strings. The OLE DB Destination expects specific types matching the SQL Server column definitions. Data Conversion bridges this gap. It is distinct from casting in a Derived Column because it preserves the original column and clearly documents what type change was made.

### Derived Column
**What it does**: Creates new columns or overwrites existing columns using SSIS expressions.  
**Why we use it**: For computed/enrichment columns that don't exist in the source — source tags (`"CSV"`, `"XML"`, `"API"`), audit timestamps (`GETDATE()`), SCD metadata (`StartDate`, `EndDate`, `IsCurrent`), version numbers, and business logic like `Quantity > 0 ? Quantity : Quantity * -1`.

### Conditional Split
**What it does**: Routes rows to different outputs based on SSIS expression conditions — like a `CASE WHEN` that physically divides the data stream.  
**Why we use it**: Data quality enforcement (route invalid rows away from the destination), business logic branching (separate buy from sell transactions), SCD routing (changed vs. unchanged rows go to different downstream paths).

### Lookup
**What it does**: Joins the data stream against a reference dataset (usually loaded into memory from a SQL query), and either enriches passing rows with reference columns or separates rows by whether they matched.  
**Why we use it**: SCD processing depends entirely on the Lookup — it compares incoming source rows against the existing dimension to determine what's new, what's changed, and what's unchanged. It is faster than a SQL JOIN for streaming scenarios because the reference table is cached in memory.

### Multicast
**What it does**: Sends every row to all connected outputs simultaneously — like broadcasting the same data to multiple consumers.  
**Why we use it**: SCD Type 6 requires one changed row to trigger three operations (expire, update current values, insert new version). Multicast fans the row out to all three paths without making multiple passes over the data.

### OLE DB Command
**What it does**: Executes a parameterized SQL statement (UPDATE, DELETE, stored procedure call) for each row passing through.  
**Why we use it**: When you need row-by-row SQL execution — expiring individual dimension rows (`UPDATE DimCampaign SET EndDate = GETDATE(), IsCurrent = 0 WHERE ID = ?`) or updating specific columns. It is slow for large datasets but indispensable for targeted updates.

### Union All
**What it does**: Combines multiple input streams into a single output stream without sorting — the SSIS equivalent of `UNION ALL` in SQL.  
**Why we use it**: After branching logic (new records down one path, updated records down another), Union All recombines them before writing to the destination. Also used to merge corrected rows back into the main flow after an error-handling branch.

### Aggregate
**What it does**: Applies grouping functions (SUM, COUNT, AVG, MAX, MIN, COUNT DISTINCT) to the data stream — the SSIS equivalent of `GROUP BY`.  
**Why we use it**: Task 4 computes total buy and sell quantities per trader per day directly in the pipeline without needing a `GROUP BY` query. It processes data in memory and is highly optimized for large volumes.

### Sort
**What it does**: Sorts the data stream by one or more columns. Can also eliminate duplicates.  
**Why we use it**: Merge Join requires both input streams to be pre-sorted on the join key. Sort is the mandatory prerequisite. Note: sorting is expensive — for large datasets, it's better to sort at the source query level using `ORDER BY`.

### Merge Join
**What it does**: Performs INNER, LEFT OUTER, or FULL OUTER joins on two **pre-sorted** streams — the streaming equivalent of SQL JOIN.  
**Why we use it**: Task 4 needs to combine the buy-summary stream with the sell-summary stream into a single row per trader per day. The FULL OUTER JOIN handles the case where a trader appears in only one stream. It requires sorted inputs (hence the Sort transformation before it).

### OLE DB Source
**What it does**: Reads data from any OLE DB-compatible database (SQL Server, Oracle, etc.) using a table name or SQL query.  
**Why we use it**: The standard way to source data from SQL Server. Task 2 uses a parameterized SQL query with `WHERE CAST(Update_Date AS DATETIME) > ?` to implement incremental loading, passing the `LastLoadDate` variable as a parameter.

### OLE DB Destination
**What it does**: Writes data to a SQL Server table using either standard row-by-row insertion or bulk "fast load" mode.  
**Why we use it**: The standard sink for loading data into the data warehouse. Tasks 1 (DFT_API) and 3 use `TABLOCK, CHECK_CONSTRAINTS` fast load options for better bulk performance.

---

## 6. Connections & Prerequisites

| Connection Name | Type | Server | Database | Used By |
|-----------------|------|--------|----------|---------|
| `MSI.DW_Assignment` | OLE DB (SQLOLEDB) | MSI | DW_Assignment | Tasks 1, 2, 3, 4 |
| `DESKTOP-20C4V96.data_warehouse` | OLE DB (SQLOLEDB) | DESKTOP-20C4V96 | data_warehouse | Task 3 (source) |
| `CSV` (Flat File) | FLATFILE | — | D:\Data Warehousing\Assignment\Air_Quality.csv | Task 1 |
| XML file | — | — | D:\Data Warehousing\...\Air_Quality.xml | Task 1 |
| REST API | HTTP (via Script) | mockapi.io | — | Task 1 |

**Required SQL Server tables** (create via Setup Files scripts):

- `dbo.air_quality_Q1` — columns: `sensor_id`, `city`, `timestamp`, `pm25`, `pm10`, `source`
- `dbo.DimCampaign` — SCD6 dimension with surrogate key, SCD columns, and history tracking
- `dbo.Campaign_Q2` — source staging table for campaigns
- `dbo.ETL_Metadata` — tracks `LastLoadDate` per `ProcessName`
- `dbo.Device_Status` — source IoT device status table
- `dbo.Device_Status_Target` — target versioned snapshot table
- `dbo.raw_trades` — source trading transactions
- `dbo.Trader_Summary` — target daily trader summary fact table

**NuGet Dependencies** (embedded in Task 1 binary):
- `Newtonsoft.Json 13.0.4` — for JSON parsing in the API Script Component

---

## 7. How to Run

### Prerequisites

- SQL Server 2019 or later
- SQL Server Data Tools (SSDT) for Visual Studio 2019+, or SQL Server Management Studio with SSIS catalog
- Run all SQL setup scripts in `Setup Files/` to create the required tables and seed the `ETL_Metadata` table

### File Path Updates Required

Before running, update the following hardcoded paths in the package connection managers:

| Package | Connection | Path to Update |
|---------|-----------|----------------|
| Task 1 | CSV Flat File | `D:\Data Warehousing\Assignment\Air_Quality.csv` |
| Task 1 | XML Source | `D:\Data Warehousing\...\Air_Quality.xml` |
| Task 1 | Script Component | `D:\Data Warehousing\Assignment\air_quality.json` (download path) |

Update server names in OLE DB connections if your SQL Server instance is not named `MSI`.

### Recommended Execution Order

Run packages in this order for a clean initial load:

1. `Task_1.dtsx` — populates `air_quality_Q1`
2. `Task_2.dtsx` — populates `DimCampaign` (requires `ETL_Metadata` seeded with a `LastLoadDate` prior to your data)
3. `Task_3.dtsx` — populates `Device_Status_Target`
4. `Task_4.dtsx` — populates `Trader_Summary`

---

## Key Design Patterns Demonstrated

| Pattern | Package | Description |
|---------|---------|-------------|
| Multi-source unified load | Task 1 | Three heterogeneous sources (CSV, XML, API) merged into one table with source tagging |
| Data quality enforcement | Tasks 1, 4 | Conditional splits reject invalid records before they reach the destination |
| Incremental loading | Task 2 | `ETL_Metadata` table tracks `LastLoadDate`; only changed records are processed |
| SCD Type 6 | Task 2 | Full historical versioning with current-value tracking on all rows |
| Snapshot versioning | Task 3 | Each data extract gets a version number; old snapshots are deactivated, not deleted |
| Stateful row-level logic | Task 4 | Script Component maintains state across rows for deduplication and business rule enforcement |
| Streaming aggregation | Task 4 | Aggregate + Sort + Merge Join computes buy/sell totals without loading into a temp table |
| Source tagging / data lineage | Task 1 | Every row is tagged with its source system for full data lineage in the warehouse |

---

*Created as part of a Data Warehousing assignment — demonstrating SSIS ETL development with Microsoft SQL Server.*

---

## 👥 Team Members
- [Mohamed Ashraf](https://github.com/moashraf18)
- [Moamen Wael](https://github.com/MoamenWael04)

## 🧑‍💻 Developed For

IS313 Data Warehousing – Spring 2026
Faculty of Computers and Artificial Intelligence - 
Cairo University

---

## 📅 Last Updated

02 May 2026

---
