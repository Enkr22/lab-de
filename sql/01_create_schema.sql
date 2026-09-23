IF SCHEMA_ID('payroll') IS NULL
    EXEC('CREATE SCHEMA payroll');
GO

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