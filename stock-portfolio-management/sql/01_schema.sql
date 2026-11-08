-- ==========================================
-- 股票交易系統 - 優化版資料表結構 (修正版)
-- ==========================================

-- 1. 建立 Users 表
CREATE TABLE Users (
    UserID INT PRIMARY KEY IDENTITY(1,1),
    UserName NVARCHAR(50) NOT NULL UNIQUE,
    Email NVARCHAR(100) UNIQUE,
    CreatedDate DATETIME DEFAULT GETDATE(),
    IsActive BIT DEFAULT 1
);
GO -- 加入 GO

-- 2. 建立 Accounts 表
CREATE TABLE Accounts (
    AccountID INT PRIMARY KEY IDENTITY(1,1),
    UserID INT NOT NULL,
    CashBalance DECIMAL(18, 2) DEFAULT 0.00 CHECK (CashBalance >= 0),
    CreatedDate DATETIME DEFAULT GETDATE(),
    LastUpdated DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    UNIQUE(UserID)
);
GO -- 加入 GO

-- 3. 建立 Stocks 表
CREATE TABLE Stocks (
    StockSymbol VARCHAR(10) PRIMARY KEY,
    CompanyName NVARCHAR(100) NOT NULL,
    Sector NVARCHAR(50),
    Market NVARCHAR(20),
    IsActive BIT DEFAULT 1,
    ListingDate DATE,
    CreatedDate DATETIME DEFAULT GETDATE()
);
GO -- 加入 GO

-- 4. 建立 DailyPrices 表
CREATE TABLE DailyPrices (
    PriceID INT PRIMARY KEY IDENTITY(1,1),
    StockSymbol VARCHAR(10) NOT NULL,
    TradeDate DATE NOT NULL,
    OpenPrice DECIMAL(18, 2),
    HighPrice DECIMAL(18, 2),
    LowPrice DECIMAL(18, 2),
    ClosePrice DECIMAL(18, 2) NOT NULL,
    Volume BIGINT,
    CreatedDate DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (StockSymbol) REFERENCES Stocks(StockSymbol),
    UNIQUE(StockSymbol, TradeDate)
);
GO -- 加入 GO

-- 5. 建立 Transactions 表
CREATE TABLE Transactions (
    TransactionID INT PRIMARY KEY IDENTITY(1,1),
    AccountID INT NOT NULL,
    StockSymbol VARCHAR(10) NOT NULL,
    TransactionType VARCHAR(4) CHECK (TransactionType IN ('BUY', 'SELL')),
    Price DECIMAL(18, 2) NOT NULL CHECK (Price > 0),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    TotalAmount AS (Price * Quantity) PERSISTED,
    Fee DECIMAL(18, 2) DEFAULT 0.00,
    Tax DECIMAL(18, 2) DEFAULT 0.00,
    TransactionDate DATETIME DEFAULT GETDATE(),
    Note NVARCHAR(200),
    FOREIGN KEY (AccountID) REFERENCES Accounts(AccountID),
    FOREIGN KEY (StockSymbol) REFERENCES Stocks(StockSymbol)
);
GO -- 加入 GO

-- 6. 建立 Holdings 表
CREATE TABLE Holdings (
    HoldingID INT PRIMARY KEY IDENTITY(1,1),
    AccountID INT NOT NULL,
    StockSymbol VARCHAR(10) NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity >= 0),
    AverageCost DECIMAL(18, 2),
    LastUpdated DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (AccountID) REFERENCES Accounts(AccountID),
    FOREIGN KEY (StockSymbol) REFERENCES Stocks(StockSymbol),
    UNIQUE(AccountID, StockSymbol)
);
GO -- 加入 GO

-- ==========================================
-- 建立索引
-- ==========================================

CREATE INDEX IX_DailyPrices_StockDate ON DailyPrices(StockSymbol, TradeDate DESC);
CREATE INDEX IX_DailyPrices_Date ON DailyPrices(TradeDate DESC);
CREATE INDEX IX_Transactions_Account ON Transactions(AccountID, TransactionDate DESC);
CREATE INDEX IX_Transactions_Stock ON Transactions(StockSymbol, TransactionDate DESC);
CREATE INDEX IX_Holdings_Account ON Holdings(AccountID);
GO -- 這裡一定要加 GO，因為下面要建立 View

-- ==========================================
-- 建立實用的 VIEW (視圖)
-- 重點修正：每個 VIEW 前後都要有 GO
-- ==========================================

-- VIEW 1: 帳戶總覽
CREATE VIEW vw_AccountSummary AS
SELECT 
    a.AccountID,
    u.UserName,
    a.CashBalance AS [現金],     -- 建議加上中括號
    ISNULL(SUM(h.Quantity * dp.ClosePrice), 0) AS [持股市值],
    a.CashBalance + ISNULL(SUM(h.Quantity * dp.ClosePrice), 0) AS [總資產]
FROM Accounts a
JOIN Users u ON a.UserID = u.UserID
LEFT JOIN Holdings h ON a.AccountID = h.AccountID
LEFT JOIN (
    SELECT StockSymbol, ClosePrice
    FROM DailyPrices
    WHERE TradeDate = (SELECT MAX(TradeDate) FROM DailyPrices)
) dp ON h.StockSymbol = dp.StockSymbol
GROUP BY a.AccountID, u.UserName, a.CashBalance;
GO -- 這裡必須加 GO

-- VIEW 2: 持股損益表
CREATE VIEW vw_HoldingsProfit AS
SELECT 
    h.AccountID,
    u.UserName,
    h.StockSymbol,
    s.CompanyName,
    h.Quantity AS [持股數量],
    h.AverageCost AS [平均成本],
    dp.ClosePrice AS [現價],
    (dp.ClosePrice - h.AverageCost) AS [單股損益],
    h.Quantity * (dp.ClosePrice - h.AverageCost) AS [總損益],
    CASE 
        WHEN h.AverageCost > 0 
        THEN ((dp.ClosePrice - h.AverageCost) / h.AverageCost * 100)
        ELSE 0 
    END AS [報酬率]
FROM Holdings h
JOIN Accounts a ON h.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
JOIN Stocks s ON h.StockSymbol = s.StockSymbol
LEFT JOIN (
    SELECT StockSymbol, ClosePrice
    FROM DailyPrices
    WHERE TradeDate = (SELECT MAX(TradeDate) FROM DailyPrices)
) dp ON h.StockSymbol = dp.StockSymbol;
GO -- 這裡必須加 GO

-- ==========================================
-- 驗證資料表結構
-- ==========================================
SELECT 
    TABLE_NAME AS [資料表名稱],
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = t.TABLE_NAME) AS [欄位數量]
FROM INFORMATION_SCHEMA.TABLES t
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;