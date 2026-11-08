-- ==========================================
-- 股票交易系統 - 預存程序與視圖 (優化版)
-- ==========================================

-- ==========================================
-- 1. 買入股票預存程序 (含手續費計算)
-- ==========================================
CREATE OR ALTER PROCEDURE sp_ExecuteBuyOrder
    @AccountID INT,
    @StockSymbol VARCHAR(10),
    @Quantity INT,
    @Price DECIMAL(18, 2),
    @FeeRate DECIMAL(5, 4) = 0.001425  -- 預設手續費 0.1425%（台股標準）
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 計算費用
    DECLARE @TotalCost DECIMAL(18, 2) = @Quantity * @Price;
    DECLARE @Fee DECIMAL(18, 2) = ROUND(@TotalCost * @FeeRate, 0);  -- 手續費四捨五入
    IF @Fee < 20 SET @Fee = 20;  -- 手續費最低 20 元
    DECLARE @TotalAmount DECIMAL(18, 2) = @TotalCost + @Fee;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 檢查帳戶是否存在
        IF NOT EXISTS (SELECT 1 FROM Accounts WHERE AccountID = @AccountID)
        BEGIN
            THROW 50000, '錯誤：帳戶不存在', 1;
        END

        -- 檢查股票是否存在
        IF NOT EXISTS (SELECT 1 FROM Stocks WHERE StockSymbol = @StockSymbol)
        BEGIN
            THROW 50002, '錯誤：股票代碼不存在', 1;
        END

        -- 檢查餘額
        DECLARE @CurrentBalance DECIMAL(18, 2);
        SELECT @CurrentBalance = CashBalance FROM Accounts WHERE AccountID = @AccountID;

        IF @CurrentBalance < @TotalAmount
        BEGIN
            DECLARE @ErrorMsg NVARCHAR(200) = 
                '交易失敗：餘額不足！需要 $' + CAST(@TotalAmount AS VARCHAR) + 
                '，但只有 $' + CAST(@CurrentBalance AS VARCHAR);
            THROW 50001, @ErrorMsg, 1;
        END

        -- 1. 扣除現金
        UPDATE Accounts 
        SET CashBalance = CashBalance - @TotalAmount,
            LastUpdated = GETDATE()
        WHERE AccountID = @AccountID;

        -- 2. 寫入交易紀錄
        INSERT INTO Transactions (AccountID, StockSymbol, TransactionType, Price, Quantity, Fee, TransactionDate)
        VALUES (@AccountID, @StockSymbol, 'BUY', @Price, @Quantity, @Fee, GETDATE());

        -- 3. 更新持股 (Holdings 表)
        IF EXISTS (SELECT 1 FROM Holdings WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol)
        BEGIN
            -- 已有持股：更新數量與平均成本
            DECLARE @CurrentQty INT, @CurrentAvgCost DECIMAL(18, 2);
            SELECT @CurrentQty = Quantity, @CurrentAvgCost = AverageCost 
            FROM Holdings 
            WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;

            DECLARE @NewQty INT = @CurrentQty + @Quantity;
            DECLARE @NewAvgCost DECIMAL(18, 2) = 
                ((@CurrentQty * @CurrentAvgCost) + (@Quantity * @Price) + @Fee) / @NewQty;

            UPDATE Holdings
            SET Quantity = @NewQty,
                AverageCost = @NewAvgCost,
                LastUpdated = GETDATE()
            WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;
        END
        ELSE
        BEGIN
            -- 新持股：新增記錄
            DECLARE @AvgCostWithFee DECIMAL(18, 2) = (@TotalCost + @Fee) / @Quantity;
            
            INSERT INTO Holdings (AccountID, StockSymbol, Quantity, AverageCost)
            VALUES (@AccountID, @StockSymbol, @Quantity, @AvgCostWithFee);
        END

        COMMIT TRANSACTION;
        
        -- 回傳成功訊息
        PRINT '✓ 買入成功！';
        PRINT '股票: ' + @StockSymbol;
        PRINT '數量: ' + CAST(@Quantity AS VARCHAR) + ' 股';
        PRINT '單價: $' + CAST(@Price AS VARCHAR);
        PRINT '手續費: $' + CAST(@Fee AS VARCHAR);
        PRINT '總花費: $' + CAST(@TotalAmount AS VARCHAR);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrState INT = ERROR_STATE();
        
        RAISERROR(@ErrMsg, @ErrSeverity, @ErrState);
    END CATCH
END;
GO

-- ==========================================
-- 2. 賣出股票預存程序 (含手續費與證交稅)
-- ==========================================
CREATE OR ALTER PROCEDURE sp_ExecuteSellOrder
    @AccountID INT,
    @StockSymbol VARCHAR(10),
    @Quantity INT,
    @Price DECIMAL(18, 2),
    @FeeRate DECIMAL(5, 4) = 0.001425,  -- 手續費 0.1425%
    @TaxRate DECIMAL(5, 4) = 0.003      -- 證交稅 0.3%
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 計算費用
    DECLARE @TotalRevenue DECIMAL(18, 2) = @Quantity * @Price;
    DECLARE @Fee DECIMAL(18, 2) = ROUND(@TotalRevenue * @FeeRate, 0);
    IF @Fee < 20 SET @Fee = 20;  -- 手續費最低 20 元
    DECLARE @Tax DECIMAL(18, 2) = ROUND(@TotalRevenue * @TaxRate, 0);  -- 證交稅
    DECLARE @NetAmount DECIMAL(18, 2) = @TotalRevenue - @Fee - @Tax;  -- 實際入帳金額

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 檢查持股是否足夠
        DECLARE @CurrentHolding INT = 0;
        SELECT @CurrentHolding = Quantity 
        FROM Holdings 
        WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;

        IF @CurrentHolding IS NULL OR @CurrentHolding < @Quantity
        BEGIN
            DECLARE @ErrorMsg NVARCHAR(200) = 
                '交易失敗：持股不足！想賣 ' + CAST(@Quantity AS VARCHAR) + 
                ' 股，但只有 ' + CAST(ISNULL(@CurrentHolding, 0) AS VARCHAR) + ' 股';
            THROW 50003, @ErrorMsg, 1;
        END

        -- 1. 增加現金
        UPDATE Accounts 
        SET CashBalance = CashBalance + @NetAmount,
            LastUpdated = GETDATE()
        WHERE AccountID = @AccountID;

        -- 2. 寫入交易紀錄
        INSERT INTO Transactions (AccountID, StockSymbol, TransactionType, Price, Quantity, Fee, Tax, TransactionDate)
        VALUES (@AccountID, @StockSymbol, 'SELL', @Price, @Quantity, @Fee, @Tax, GETDATE());

        -- 3. 更新持股
        DECLARE @NewQty INT = @CurrentHolding - @Quantity;
        
        IF @NewQty = 0
        BEGIN
            -- 全部賣出：刪除持股記錄
            DELETE FROM Holdings 
            WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;
        END
        ELSE
        BEGIN
            -- 部分賣出：更新數量
            UPDATE Holdings
            SET Quantity = @NewQty,
                LastUpdated = GETDATE()
            WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;
        END

        COMMIT TRANSACTION;
        
        -- 回傳成功訊息
        PRINT '✓ 賣出成功！';
        PRINT '股票: ' + @StockSymbol;
        PRINT '數量: ' + CAST(@Quantity AS VARCHAR) + ' 股';
        PRINT '單價: $' + CAST(@Price AS VARCHAR);
        PRINT '手續費: $' + CAST(@Fee AS VARCHAR);
        PRINT '證交稅: $' + CAST(@Tax AS VARCHAR);
        PRINT '實收金額: $' + CAST(@NetAmount AS VARCHAR);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrState INT = ERROR_STATE();
        
        RAISERROR(@ErrMsg, @ErrSeverity, @ErrState);
    END CATCH
END;
GO

-- ==========================================
-- 3. 持倉查詢 VIEW (從 Holdings 表讀取)
-- ==========================================
CREATE OR ALTER VIEW vw_CurrentHoldings AS
SELECT 
    a.AccountID,
    u.UserName AS 用戶名稱,
    h.StockSymbol AS 股票代碼,
    s.CompanyName AS 公司名稱,
    s.Sector AS 產業,
    h.Quantity AS 持股數量,
    h.AverageCost AS 平均成本,
    dp.ClosePrice AS 現價,
    (dp.ClosePrice - h.AverageCost) AS 單股損益,
    h.Quantity * (dp.ClosePrice - h.AverageCost) AS 總損益,
    h.Quantity * h.AverageCost AS 成本總額,
    h.Quantity * dp.ClosePrice AS 市值,
    CASE 
        WHEN h.AverageCost > 0 
        THEN ROUND(((dp.ClosePrice - h.AverageCost) / h.AverageCost * 100), 2)
        ELSE 0 
    END AS 報酬率,
    h.LastUpdated AS 更新時間
FROM Holdings h
JOIN Accounts a ON h.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
JOIN Stocks s ON h.StockSymbol = s.StockSymbol
LEFT JOIN (
    -- 取得最新收盤價
    SELECT StockSymbol, ClosePrice, TradeDate
    FROM DailyPrices
    WHERE TradeDate = (SELECT MAX(TradeDate) FROM DailyPrices)
) dp ON h.StockSymbol = dp.StockSymbol
WHERE h.Quantity > 0;  -- 只顯示有持股的記錄
GO

-- ==========================================
-- 4. 交易歷史查詢 VIEW
-- ==========================================
CREATE OR ALTER VIEW vw_TransactionHistory AS
SELECT 
    t.TransactionID,
    u.UserName AS 用戶名稱,
    t.StockSymbol AS 股票代碼,
    s.CompanyName AS 公司名稱,
    t.TransactionType AS 交易類型,
    t.Quantity AS 數量,
    t.Price AS 單價,
    t.TotalAmount AS 交易金額,
    t.Fee AS 手續費,
    t.Tax AS 證交稅,
    CASE 
        WHEN t.TransactionType = 'BUY' THEN t.TotalAmount + t.Fee
        ELSE t.TotalAmount - t.Fee - t.Tax
    END AS 實際金額,
    t.TransactionDate AS 交易時間,
    t.Note AS 備註
FROM Transactions t
JOIN Accounts a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
JOIN Stocks s ON t.StockSymbol = s.StockSymbol;
GO

-- ==========================================
-- 5. 帳戶總覽 VIEW (現金 + 持股市值)
-- ==========================================
CREATE OR ALTER VIEW vw_AccountOverview AS
SELECT 
    a.AccountID,
    u.UserName AS 用戶名稱,
    u.Email AS 信箱,
    a.CashBalance AS 現金餘額,
    ISNULL(SUM(h.Quantity * dp.ClosePrice), 0) AS 持股市值,
    a.CashBalance + ISNULL(SUM(h.Quantity * dp.ClosePrice), 0) AS 總資產,
    COUNT(DISTINCT h.StockSymbol) AS 持股檔數,
    (SELECT COUNT(*) FROM Transactions WHERE AccountID = a.AccountID) AS 交易次數,
    a.LastUpdated AS 最後更新時間
FROM Accounts a
JOIN Users u ON a.UserID = u.UserID
LEFT JOIN Holdings h ON a.AccountID = h.AccountID
LEFT JOIN (
    SELECT StockSymbol, ClosePrice
    FROM DailyPrices
    WHERE TradeDate = (SELECT MAX(TradeDate) FROM DailyPrices)
) dp ON h.StockSymbol = dp.StockSymbol
GROUP BY a.AccountID, u.UserName, u.Email, a.CashBalance, a.LastUpdated;
GO

-- ==========================================
-- 測試範例
-- ==========================================
/*
-- 執行買入
EXEC sp_ExecuteBuyOrder 
    @AccountID = 1, 
    @StockSymbol = '2330', 
    @Quantity = 1000, 
    @Price = 580.00;

-- 執行賣出
EXEC sp_ExecuteSellOrder 
    @AccountID = 1, 
    @StockSymbol = '2330', 
    @Quantity = 500, 
    @Price = 590.00;

-- 查詢持倉
SELECT * FROM vw_CurrentHoldings;

-- 查詢交易紀錄
SELECT * FROM vw_TransactionHistory ORDER BY 交易時間 DESC;

-- 查詢帳戶總覽
SELECT * FROM vw_AccountOverview;
*/