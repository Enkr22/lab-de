/*
    01_create_schema.sql
    Esquema del sistema origen de nómina sintético (fase 1).
    Requisito: haber corrido 00_create_database.sql.
    Idempotente: se puede correr N veces sin error.
*/

USE LabNomina;
GO

IF SCHEMA_ID('payroll') IS NULL
    EXEC('CREATE SCHEMA payroll');
GO

/* ---------- Country ---------- */
IF OBJECT_ID('payroll.Country', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.Country (
        CountryCode   CHAR(2)       NOT NULL,
        Name          NVARCHAR(100) NOT NULL,
        CurrencyCode  CHAR(3)       NOT NULL,
        PayFrequency  VARCHAR(10)   NOT NULL,
        CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_Country_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_Country_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Country PRIMARY KEY (CountryCode),
        CONSTRAINT CK_Country_PayFrequency CHECK (PayFrequency IN ('BIWEEKLY', 'MONTHLY'))
    );
END;
GO

/* ---------- Department ---------- */
IF OBJECT_ID('payroll.Department', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.Department (
        DepartmentId  INT IDENTITY(1,1) NOT NULL,
        CountryCode   CHAR(2)           NOT NULL,
        Name          NVARCHAR(100)     NOT NULL,
        CreatedAt     DATETIME2(3)      NOT NULL CONSTRAINT DF_Department_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt     DATETIME2(3)      NOT NULL CONSTRAINT DF_Department_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Department PRIMARY KEY (DepartmentId),
        CONSTRAINT FK_Department_Country FOREIGN KEY (CountryCode) REFERENCES payroll.Country (CountryCode),
        CONSTRAINT UQ_Department_CountryCode_Name UNIQUE (CountryCode, Name)
    );
END;
GO

/* ---------- Employee ---------- */
IF OBJECT_ID('payroll.Employee', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.Employee (
        EmployeeId  INT IDENTITY(1,1) NOT NULL,
        FirstName   NVARCHAR(100)     NOT NULL,
        LastName    NVARCHAR(100)     NOT NULL,
        BirthDate   DATE              NULL,
        CreatedAt   DATETIME2(3)      NOT NULL CONSTRAINT DF_Employee_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt   DATETIME2(3)      NOT NULL CONSTRAINT DF_Employee_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Employee PRIMARY KEY (EmployeeId)
    );
END;
GO

/* ---------- Employment ---------- */
IF OBJECT_ID('payroll.Employment', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.Employment (
        EmploymentId       INT IDENTITY(1,1) NOT NULL,
        EmployeeId         INT               NOT NULL,
        DepartmentId       INT               NOT NULL,
        JobTitle           NVARCHAR(100)     NOT NULL,
        MonthlySalary      DECIMAL(18,2)     NOT NULL,
        HireDate           DATE              NOT NULL,
        TerminationDate    DATE              NULL,
        TerminationReason  VARCHAR(20)       NULL,
        CreatedAt          DATETIME2(3)      NOT NULL CONSTRAINT DF_Employment_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt          DATETIME2(3)      NOT NULL CONSTRAINT DF_Employment_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Employment PRIMARY KEY (EmploymentId),
        CONSTRAINT FK_Employment_Employee FOREIGN KEY (EmployeeId) REFERENCES payroll.Employee (EmployeeId),
        CONSTRAINT FK_Employment_Department FOREIGN KEY (DepartmentId) REFERENCES payroll.Department (DepartmentId),
        CONSTRAINT CK_Employment_MonthlySalary CHECK (MonthlySalary > 0),
        CONSTRAINT CK_Employment_TerminationDate CHECK (TerminationDate >= HireDate),
        CONSTRAINT CK_Employment_TerminationReason CHECK (TerminationReason IN ('RESIGNATION', 'DISMISSAL', 'END_OF_CONTRACT')),
        CONSTRAINT CK_Employment_Termination CHECK (
            (TerminationDate IS NULL AND TerminationReason IS NULL)
            OR (TerminationDate IS NOT NULL AND TerminationReason IS NOT NULL)
        )
    );
END;
GO

/* ---------- PayrollConcept ---------- */
IF OBJECT_ID('payroll.PayrollConcept', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.PayrollConcept (
        ConceptId    INT IDENTITY(1,1) NOT NULL,
        CountryCode  CHAR(2)           NOT NULL,
        Code         VARCHAR(5)        NOT NULL,
        Name         NVARCHAR(100)     NOT NULL,
        ConceptType  VARCHAR(10)       NOT NULL,
        CreatedAt    DATETIME2(3)      NOT NULL CONSTRAINT DF_PayrollConcept_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt    DATETIME2(3)      NOT NULL CONSTRAINT DF_PayrollConcept_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_PayrollConcept PRIMARY KEY (ConceptId),
        CONSTRAINT FK_PayrollConcept_Country FOREIGN KEY (CountryCode) REFERENCES payroll.Country (CountryCode),
        CONSTRAINT UQ_PayrollConcept_CountryCode_Code UNIQUE (CountryCode, Code),
        CONSTRAINT CK_PayrollConcept_ConceptType CHECK (ConceptType IN ('EARNING', 'DEDUCTION'))
    );
END;
GO

/* ---------- PayrollPeriod ---------- */
IF OBJECT_ID('payroll.PayrollPeriod', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.PayrollPeriod (
        PeriodId     INT IDENTITY(1,1) NOT NULL,
        CountryCode  CHAR(2)           NOT NULL,
        StartDate    DATE              NOT NULL,
        EndDate      DATE              NOT NULL,
        PayDate      DATE              NOT NULL,
        CreatedAt    DATETIME2(3)      NOT NULL CONSTRAINT DF_PayrollPeriod_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt    DATETIME2(3)      NOT NULL CONSTRAINT DF_PayrollPeriod_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_PayrollPeriod PRIMARY KEY (PeriodId),
        CONSTRAINT FK_PayrollPeriod_Country FOREIGN KEY (CountryCode) REFERENCES payroll.Country (CountryCode),
        CONSTRAINT UQ_PayrollPeriod_CountryCode_StartDate UNIQUE (CountryCode, StartDate),
        CONSTRAINT CK_PayrollPeriod_EndDate CHECK (EndDate >= StartDate)
    );
END;
GO

/* ---------- PayrollMovement ---------- */
IF OBJECT_ID('payroll.PayrollMovement', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.PayrollMovement (
        MovementId    BIGINT IDENTITY(1,1) NOT NULL,
        EmploymentId  INT                  NOT NULL,
        PeriodId      INT                  NOT NULL,
        ConceptId     INT                  NOT NULL,
        Amount        DECIMAL(18,2)        NOT NULL,
        CreatedAt     DATETIME2(3)         NOT NULL CONSTRAINT DF_PayrollMovement_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt     DATETIME2(3)         NOT NULL CONSTRAINT DF_PayrollMovement_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_PayrollMovement PRIMARY KEY (MovementId),
        CONSTRAINT FK_PayrollMovement_Employment FOREIGN KEY (EmploymentId) REFERENCES payroll.Employment (EmploymentId),
        CONSTRAINT FK_PayrollMovement_PayrollPeriod FOREIGN KEY (PeriodId) REFERENCES payroll.PayrollPeriod (PeriodId),
        CONSTRAINT FK_PayrollMovement_PayrollConcept FOREIGN KEY (ConceptId) REFERENCES payroll.PayrollConcept (ConceptId),
        CONSTRAINT CK_PayrollMovement_Amount CHECK (Amount >= 0)
        );
END;
GO

/* ---------- Settlement ---------- */
IF OBJECT_ID('payroll.Settlement', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.Settlement (
        SettlementId    INT IDENTITY(1,1) NOT NULL,
        EmploymentId    INT               NOT NULL,
        SettlementDate  DATE              NOT NULL,
        Status          VARCHAR(10)       NOT NULL,
        CreatedAt       DATETIME2(3)      NOT NULL CONSTRAINT DF_Settlement_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt       DATETIME2(3)      NOT NULL CONSTRAINT DF_Settlement_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Settlement PRIMARY KEY (SettlementId),
        CONSTRAINT FK_Settlement_Employment FOREIGN KEY (EmploymentId) REFERENCES payroll.Employment (EmploymentId),
        CONSTRAINT UQ_Settlement_EmploymentId UNIQUE (EmploymentId),
        CONSTRAINT CK_Settlement_Status CHECK (Status IN ('DRAFT', 'PAID', 'CANCELLED')),
    );
END;
GO

/* ---------- SettlementLine ---------- */
IF OBJECT_ID('payroll.SettlementLine', 'U') IS NULL
BEGIN
    CREATE TABLE payroll.SettlementLine (
        SettlementLineId  BIGINT IDENTITY(1,1) NOT NULL,
        SettlementId      INT                  NOT NULL,
        ConceptId         INT                  NOT NULL,
        Amount            DECIMAL(18,2)        NOT NULL,
        CreatedAt         DATETIME2(3)         NOT NULL CONSTRAINT DF_SettlementLine_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt         DATETIME2(3)         NOT NULL CONSTRAINT DF_SettlementLine_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_SettlementLine PRIMARY KEY (SettlementLineId),
        CONSTRAINT FK_SettlementLine_Settlement FOREIGN KEY (SettlementId) REFERENCES payroll.Settlement (SettlementId),
        CONSTRAINT FK_SettlementLine_PayrollConcept FOREIGN KEY (ConceptId) REFERENCES payroll.PayrollConcept (ConceptId),
        CONSTRAINT CK_SettlementLine_Amount CHECK (Amount >= 0)

    );
END;
GO