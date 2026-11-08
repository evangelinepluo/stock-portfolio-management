-- ==========================================
-- 股票交易系統 - Trigger (觸發器) 範例
-- ==========================================

USE StockTradingDB1;
GO

-- ==========================================
-- 1. AFTER Trigger - 自動更新帳戶最後更新時間
-- ==========================================
-- 目的：當帳戶現金餘額改變時，自動更新 LastUpdated 欄位

CREATE OR ALTER TRIGGER trg_Accounts_AfterUpdate
ON Accounts
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 只在現金餘額改變時更新時間
    IF UPDATE(CashBalance)
    BEGIN
        UPDATE Accounts
        SET LastUpdated = GETDATE()
        WHERE AccountID IN (SELECT AccountID FROM inserted);
        
        PRINT N'✓ 帳戶最後更新時間已自動更新';
    END
END;
GO

-- ==========================================
-- 2. AFTER Trigger - 防止現金餘額變成負數
-- ==========================================
-- 目的：確保資料完整性，如果現金變負數就 Rollback

CREATE OR ALTER TRIGGER trg_Accounts_PreventNegativeBalance
ON Accounts
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 檢查是否有帳戶現金變成負數
    IF EXISTS (
        SELECT 1 
        FROM inserted 
        WHERE CashBalance < 0
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50010, N'錯誤：現金餘額不可為負數！交易已取消。', 1;
    END
    ELSE
    BEGIN
        PRINT N'✓ 現金餘額檢查通過';
    END
END;
GO

-- ==========================================
-- 3. AFTER Trigger - 記錄交易後自動更新持股
-- ==========================================
-- 目的：每次 Transactions 新增記錄時，自動同步 Holdings

CREATE OR ALTER TRIGGER trg_Transactions_AfterInsert
ON Transactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @AccountID INT;
    DECLARE @StockSymbol VARCHAR(10);
    DECLARE @TransType VARCHAR(4);
    DECLARE @Quantity INT;
    DECLARE @Price DECIMAL(18, 2);
    
    -- 從插入的資料取得交易資訊
    SELECT 
        @AccountID = AccountID,
        @StockSymbol = StockSymbol,
        @TransType = TransactionType,
        @Quantity = Quantity,
        @Price = Price
    FROM inserted;
    
    -- 根據交易類型更新持股
    IF @TransType = 'BUY'
    BEGIN
        -- 買入：更新或新增持股
        IF EXISTS (SELECT 1 FROM Holdings WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol)
        BEGIN
            -- 已有持股：更新數量和平均成本
            DECLARE @OldQty INT, @OldAvgCost DECIMAL(18, 2);
            
            SELECT @OldQty = Quantity, @OldAvgCost = AverageCost
            FROM Holdings
            WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;
            
            DECLARE @NewQty INT = @OldQty + @Quantity;
            DECLARE @NewAvgCost DECIMAL(18, 2) = 
                ((@OldQty * @OldAvgCost) + (@Quantity * @Price)) / @NewQty;
            
            UPDATE Holdings
            SET Quantity = @NewQty,
                AverageCost = @NewAvgCost,
                LastUpdated = GETDATE()
            WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;
            
            PRINT N'✓ 持股已更新 (買入)';
        END
        ELSE
        BEGIN
            -- 新持股：新增記錄
            INSERT INTO Holdings (AccountID, StockSymbol, Quantity, AverageCost)
            VALUES (@AccountID, @StockSymbol, @Quantity, @Price);
            
            PRINT N'✓ 新增持股記錄 (買入)';
        END
    END
    ELSE IF @TransType = 'SELL'
    BEGIN
        -- 賣出：減少持股數量
        UPDATE Holdings
        SET Quantity = Quantity - @Quantity,
            LastUpdated = GETDATE()
        WHERE AccountID = @AccountID AND StockSymbol = @StockSymbol;
        
        -- 如果賣光了，刪除持股記錄
        DELETE FROM Holdings
        WHERE AccountID = @AccountID 
          AND StockSymbol = @StockSymbol 
          AND Quantity = 0;
        
        PRINT N'✓ 持股已更新 (賣出)';
    END
END;
GO

-- ==========================================
-- 4. INSTEAD OF Trigger - 防止刪除有持股的帳戶
-- ==========================================
-- 目的：保護資料完整性，不允許刪除還有持股的帳戶

CREATE OR ALTER TRIGGER trg_Accounts_InsteadOfDelete
ON Accounts
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @AccountID INT;
    
    -- 檢查要刪除的帳戶
    DECLARE account_cursor CURSOR FOR
    SELECT AccountID FROM deleted;
    
    OPEN account_cursor;
    FETCH NEXT FROM account_cursor INTO @AccountID;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- 檢查是否還有持股
        IF EXISTS (SELECT 1 FROM Holdings WHERE AccountID = @AccountID AND Quantity > 0)
        BEGIN
            PRINT N'✗ 帳戶 ' + CAST(@AccountID AS NVARCHAR) + N' 還有持股，無法刪除！';
            PRINT N'請先賣出所有股票後再刪除帳戶。';
        END
        ELSE
        BEGIN
            -- 沒有持股，允許刪除
            DELETE FROM Accounts WHERE AccountID = @AccountID;
            PRINT N'✓ 帳戶 ' + CAST(@AccountID AS NVARCHAR) + N' 已刪除';
        END
        
        FETCH NEXT FROM account_cursor INTO @AccountID;
    END
    
    CLOSE account_cursor;
    DEALLOCATE account_cursor;
END;
GO

-- ==========================================
-- 5. AFTER Trigger - 防止刪除有交易記錄的股票
-- ==========================================
-- 目的：保護歷史資料完整性

CREATE OR ALTER TRIGGER trg_Stocks_PreventDelete
ON Stocks
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 檢查是否有交易記錄
    IF EXISTS (
        SELECT 1 
        FROM Transactions t
        INNER JOIN deleted d ON t.StockSymbol = d.StockSymbol
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50011, N'錯誤：此股票有交易記錄，無法刪除！請改用停用功能。', 1;
    END
END;
GO

-- ==========================================
-- 6. AFTER Trigger - 記錄股價異動歷史
-- ==========================================
-- 目的：建立股價變動審計軌跡

-- 先建立歷史記錄表
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'PriceChangeLog')
BEGIN
    CREATE TABLE PriceChangeLog (
        LogID INT PRIMARY KEY IDENTITY(1,1),
        StockSymbol VARCHAR(10),
        OldPrice DECIMAL(18, 2),
        NewPrice DECIMAL(18, 2),
        ChangePercent DECIMAL(10, 2),
        ChangeDate DATETIME DEFAULT GETDATE(),
        ChangedBy NVARCHAR(100) DEFAULT SYSTEM_USER
    );
    PRINT N'✓ PriceChangeLog 表已建立';
END
GO

-- 建立 Trigger
CREATE OR ALTER TRIGGER trg_DailyPrices_LogChanges
ON DailyPrices
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 只在收盤價改變時記錄
    IF UPDATE(ClosePrice)
    BEGIN
        INSERT INTO PriceChangeLog (StockSymbol, OldPrice, NewPrice, ChangePercent)
        SELECT 
            i.StockSymbol,
            d.ClosePrice AS OldPrice,
            i.ClosePrice AS NewPrice,
            CASE 
                WHEN d.ClosePrice > 0 
                THEN ((i.ClosePrice - d.ClosePrice) / d.ClosePrice * 100)
                ELSE 0 
            END AS ChangePercent
        FROM inserted i
        INNER JOIN deleted d ON i.PriceID = d.PriceID
        WHERE i.ClosePrice <> d.ClosePrice;
        
        PRINT N'✓ 股價變動已記錄';
    END
END;
GO

-- ==========================================
-- 測試 Trigger
-- ==========================================

PRINT N'';
PRINT N'==========================================';
PRINT N'開始測試 Trigger';
PRINT N'==========================================';
GO

-- 測試 1: 測試現金餘額負數檢查
PRINT N'';
PRINT N'【測試 1】嘗試將現金設為負數（應該被阻止）';
BEGIN TRY
    UPDATE Accounts SET CashBalance = -100 WHERE AccountID = 1;
END TRY
BEGIN CATCH
    PRINT N'✓ 測試成功：' + ERROR_MESSAGE();
END CATCH
GO

-- 測試 2: 測試正常的現金更新
PRINT N'';
PRINT N'【測試 2】正常更新現金餘額';
UPDATE Accounts SET CashBalance = CashBalance + 1000 WHERE AccountID = 1;
SELECT AccountID, CashBalance, LastUpdated 
FROM Accounts 
WHERE AccountID = 1;
GO

-- 測試 3: 測試刪除有持股的帳戶
PRINT N'';
PRINT N'【測試 3】嘗試刪除有持股的帳戶（應該被阻止）';
DELETE FROM Accounts WHERE AccountID = 1;
GO

-- 測試 4: 查看股價變動記錄
PRINT N'';
PRINT N'【測試 4】更新股價並查看記錄';
UPDATE DailyPrices 
SET ClosePrice = ClosePrice * 1.05 
WHERE StockSymbol = '2330' 
  AND TradeDate = (SELECT MAX(TradeDate) FROM DailyPrices WHERE StockSymbol = '2330');

SELECT TOP 5 * FROM PriceChangeLog ORDER BY ChangeDate DESC;
GO

-- ==========================================
-- 查詢所有 Trigger
-- ==========================================
PRINT N'';
PRINT N'==========================================';
PRINT N'系統中所有的 Trigger：';
PRINT N'==========================================';

SELECT 
    t.name AS Trigger名稱,
    OBJECT_NAME(t.parent_id) AS 資料表,
    CASE 
        WHEN t.is_instead_of_trigger = 1 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END AS 類型,
    t.is_disabled AS 是否停用
FROM sys.triggers t
WHERE t.parent_class = 1  -- 只顯示資料表的 Trigger
ORDER BY OBJECT_NAME(t.parent_id), t.name;
GO

PRINT N'';
PRINT N'==========================================';
PRINT N'Trigger 建立完成！';
PRINT N'==========================================';