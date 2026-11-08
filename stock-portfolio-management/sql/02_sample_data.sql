-- ==========================================
-- 台股與ETF完整資料插入腳本（修正版）
-- ==========================================

-- 清除舊資料（選用，如果要重新開始的話）
-- DELETE FROM DailyPrices;
-- DELETE FROM Holdings;
-- DELETE FROM Transactions;
-- DELETE FROM Accounts;
-- DELETE FROM Users;
-- DELETE FROM Stocks;

-- ==========================================
-- 1. ETF 資料
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'0050', N'元大台灣50', N'ETF'),
(N'0056', N'元大高股息', N'ETF'),
(N'00878', N'國泰永續高股息', N'ETF'),
(N'00919', N'群益台灣精選高息', N'ETF'),
(N'006208', N'富邦台50', N'ETF');

-- ==========================================
-- 2. 半導體產業
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'2330', N'台積電', N'半導體'),
(N'2454', N'聯發科', N'半導體'),
(N'2303', N'聯電', N'半導體'),
(N'3034', N'聯詠', N'半導體'),
(N'2379', N'瑞昱', N'半導體'),
(N'3443', N'創意', N'半導體'),
(N'2408', N'南亞科', N'半導體'),
(N'3231', N'緯創', N'半導體');

-- ==========================================
-- 3. 電子零組件與代工
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'2317', N'鴻海', N'電子零組件'),
(N'2382', N'廣達', N'電腦及週邊'),
(N'2308', N'台達電', N'電子零組件'),
(N'2357', N'華碩', N'電腦及週邊'),
(N'2356', N'英業達', N'電腦及週邊'),
(N'2324', N'仁寶', N'電腦及週邊'),
(N'2327', N'國巨', N'電子零組件');

-- ==========================================
-- 4. 金融股
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'2881', N'富邦金', N'金融保險'),
(N'2882', N'國泰金', N'金融保險'),
(N'2884', N'玉山金', N'金融保險'),
(N'2886', N'兆豐金', N'金融保險'),
(N'2891', N'中信金', N'金融保險'),
(N'2892', N'第一金', N'金融保險'),
(N'2880', N'華南金', N'金融保險'),
(N'5880', N'合庫金', N'金融保險');

-- ==========================================
-- 5. 傳統產業（塑化、鋼鐵、水泥）
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'1301', N'台塑', N'塑膠'),
(N'1303', N'南亞', N'塑膠'),
(N'1326', N'台化', N'塑膠'),
(N'2002', N'中鋼', N'鋼鐵'),
(N'1101', N'台泥', N'水泥'),
(N'1102', N'亞泥', N'水泥');

-- ==========================================
-- 6. 食品與民生消費
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'1216', N'統一', N'食品'),
(N'2912', N'統一超', N'貿易百貨'),
(N'2915', N'潤泰全', N'貿易百貨');

-- ==========================================
-- 7. 航運股
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'2603', N'長榮', N'航運'),
(N'2609', N'陽明', N'航運'),
(N'2615', N'萬海', N'航運');

-- ==========================================
-- 8. 面板與光電
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'2409', N'友達', N'光電'),
(N'3481', N'群創', N'光電');

-- ==========================================
-- 9. 電信股
-- ==========================================
INSERT INTO Stocks (StockSymbol, CompanyName, Sector) VALUES 
(N'2412', N'中華電', N'通信網路'),
(N'4904', N'遠傳', N'通信網路'),
(N'3045', N'台灣大', N'通信網路');

-- ==========================================
-- 10. 建立測試用戶
-- ==========================================
INSERT INTO Users (UserName, Email) VALUES 
(N'TestUser', N'test@example.com'),
(N'InvestorA', N'investor_a@example.com'),
(N'InvestorB', N'investor_b@example.com'),
(N'ETFLover', N'etf_lover@example.com'),
(N'ValueInvestor', N'value@example.com');

-- ==========================================
-- 11. 為每個用戶建立帳戶
-- ==========================================
-- TestUser: 100萬現金
INSERT INTO Accounts (UserID, CashBalance) VALUES (1, 1000000);

-- InvestorA: 200萬現金
INSERT INTO Accounts (UserID, CashBalance) VALUES (2, 2000000);

-- InvestorB: 150萬現金
INSERT INTO Accounts (UserID, CashBalance) VALUES (3, 1500000);

-- ETFLover: 300萬現金
INSERT INTO Accounts (UserID, CashBalance) VALUES (4, 3000000);

-- ValueInvestor: 500萬現金
INSERT INTO Accounts (UserID, CashBalance) VALUES (5, 5000000);

-- ==========================================
-- 12. 建立一些模擬持股（選用）
-- ==========================================
-- TestUser 持有台積電 10張 和 0050 ETF 5張
INSERT INTO Holdings (AccountID, StockSymbol, Quantity, AverageCost) VALUES 
(1, N'2330', 10000, 580.50),  -- 10張 台積電 平均成本 580.5
(1, N'0050', 5000, 145.20);   -- 5張 0050 平均成本 145.2

-- InvestorA 持有多檔金融股
INSERT INTO Holdings (AccountID, StockSymbol, Quantity, AverageCost) VALUES 
(2, N'2881', 20000, 65.30),   -- 20張 富邦金
(2, N'2882', 15000, 58.80),   -- 15張 國泰金
(2, N'2886', 10000, 35.60);   -- 10張 兆豐金

-- ETFLover 專注投資 ETF
INSERT INTO Holdings (AccountID, StockSymbol, Quantity, AverageCost) VALUES 
(4, N'0050', 30000, 142.50),   -- 30張 0050
(4, N'0056', 40000, 32.80),    -- 40張 0056
(4, N'00878', 25000, 18.50);   -- 25張 00878

-- ValueInvestor 價值投資組合
INSERT INTO Holdings (AccountID, StockSymbol, Quantity, AverageCost) VALUES 
(5, N'2330', 50000, 550.00),   -- 50張 台積電
(5, N'2454', 20000, 890.00),   -- 20張 聯發科
(5, N'2308', 15000, 320.00),   -- 15張 台達電
(5, N'2412', 30000, 115.50);   -- 30張 中華電

-- ==========================================
-- 13. 建立一些交易記錄（選用）
-- ==========================================
-- TestUser 的交易記錄
INSERT INTO Transactions (AccountID, StockSymbol, TransactionType, Quantity, Price, TransactionDate) VALUES 
(1, N'2330', N'BUY', 10000, 580.50, '2024-01-15'),
(1, N'0050', N'BUY', 5000, 145.20, '2024-02-20');

-- InvestorA 的交易記錄
INSERT INTO Transactions (AccountID, StockSymbol, TransactionType, Quantity, Price, TransactionDate) VALUES 
(2, N'2881', N'BUY', 20000, 65.30, '2024-01-10'),
(2, N'2882', N'BUY', 15000, 58.80, '2024-01-25'),
(2, N'2886', N'BUY', 10000, 35.60, '2024-02-05');

-- ETFLover 的交易記錄
INSERT INTO Transactions (AccountID, StockSymbol, TransactionType, Quantity, Price, TransactionDate) VALUES 
(4, N'0050', N'BUY', 30000, 142.50, '2024-01-05'),
(4, N'0056', N'BUY', 40000, 32.80, '2024-01-20'),
(4, N'00878', N'BUY', 25000, 18.50, '2024-02-10');

-- ValueInvestor 的交易記錄
INSERT INTO Transactions (AccountID, StockSymbol, TransactionType, Quantity, Price, TransactionDate) VALUES 
(5, N'2330', N'BUY', 50000, 550.00, '2023-12-15'),
(5, N'2454', N'BUY', 20000, 890.00, '2024-01-08'),
(5, N'2308', N'BUY', 15000, 320.00, '2024-01-22'),
(5, N'2412', N'BUY', 30000, 115.50, '2024-02-01');

-- ==========================================
-- 14. 查詢驗證
-- ==========================================
PRINT N'==========================================';
PRINT N'資料插入完成！以下是統計資訊：';
PRINT N'==========================================';
GO

-- 查看所有資料統計
SELECT N'股票總數' AS 類別, COUNT(*) AS 數量 FROM Stocks
UNION ALL
SELECT N'用戶總數', COUNT(*) FROM Users
UNION ALL
SELECT N'帳戶總數', COUNT(*) FROM Accounts
UNION ALL
SELECT N'持股記錄', COUNT(*) FROM Holdings
UNION ALL
SELECT N'交易記錄', COUNT(*) FROM Transactions;

-- 查看各產業股票數量
SELECT Sector AS 產業, COUNT(*) AS 股票數量
FROM Stocks
GROUP BY Sector
ORDER BY COUNT(*) DESC;

-- 查看所有用戶的帳戶餘額
SELECT 
    u.UserName AS 用戶名稱,
    a.CashBalance AS 現金餘額,
    COUNT(h.StockSymbol) AS 持股檔數
FROM Users u
JOIN Accounts a ON u.UserID = a.UserID
LEFT JOIN Holdings h ON a.AccountID = h.AccountID
GROUP BY u.UserName, a.CashBalance
ORDER BY a.CashBalance DESC;