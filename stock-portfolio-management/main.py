from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import os
import pyodbc
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal

app = FastAPI(
    title="股票交易系統 API",
    description="完整的股票交易與投資組合管理系統",
    version="1.0.0"
)

# 設定 CORS（讓前端可以呼叫 API）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
# 資料庫連線設定 (Mac 修正版)
# ==========================================
# ⚠️ 請在下方填入你的 SQL Server 密碼
db_password = os.environ.get("DB_PASSWORD", "")

CONN_STR = (
    "Driver={ODBC Driver 18 for SQL Server};" # Mac 通常使用 Driver 17 或 18
    "Server=localhost;"                       # Mac 本機 (Docker) 通常是 localhost
    "Database=StockTradingDB1;"                # 請確認你的資料庫名稱正確
    "UID=sa;"                                 # Mac Docker 預設帳號通常是 sa
    f"PWD={db_password};"
    "TrustServerCertificate=yes;"             # Mac/Linux 必加，忽略 SSL 憑證檢查
)

def get_db_connection():
    """取得資料庫連線"""
    try:
        return pyodbc.connect(CONN_STR)
    except Exception as e:
        print(f"連線錯誤細節: {str(e)}") # 印出錯誤在終端機方便除錯
        raise HTTPException(status_code=500, detail=f"資料庫連線失敗: {str(e)}")

def get_db():
    return pyodbc.connect(CONN_STR)

# ==========================================
# Pydantic 資料模型定義
# ==========================================
class TradeRequest(BaseModel):
    account_id: int
    stock_symbol: str
    quantity: int
    price: float
    
class BuyRequest(BaseModel):
    account_id: int = Field(..., description="帳戶ID")
    stock_symbol: str = Field(..., description="股票代碼", max_length=10)
    quantity: int = Field(..., gt=0, description="購買數量（股）")
    price: float = Field(..., gt=0, description="購買單價")

class SellRequest(BaseModel):
    account_id: int = Field(..., description="帳戶ID")
    stock_symbol: str = Field(..., description="股票代碼", max_length=10)
    quantity: int = Field(..., gt=0, description="賣出數量（股）")
    price: float = Field(..., gt=0, description="賣出單價")

class HoldingItem(BaseModel):
    stock_symbol: str
    company_name: str
    quantity: int
    average_cost: float
    current_price: float
    market_value: float
    total_profit: float
    return_rate: float

class AccountSummary(BaseModel):
    account_id: int
    user_name: str
    cash_balance: float
    stock_value: float
    total_assets: float
    holdings_count: int

class TransactionHistory(BaseModel):
    transaction_id: int
    stock_symbol: str
    company_name: str
    transaction_type: str
    quantity: int
    price: float
    fee: float
    tax: float
    transaction_date: datetime

class StockInfo(BaseModel):
    stock_symbol: str
    company_name: str
    sector: str
    latest_price: Optional[float]
    trade_date: Optional[date]

# ==========================================
# API 路由
# ==========================================

@app.get("/", tags=["系統"])
def read_root():
    """API 首頁"""
    return {
        "message": "股票交易系統 API 運行中！",
        "docs": "/docs",
        "redoc": "/redoc"
    }

@app.get("/health", tags=["系統"])
def health_check():
    """健康檢查"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            return {"status": "healthy", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"系統異常: {str(e)}")

@app.get("/health")
def health():
    return {"status": "ok"}

# 2. 交易紀錄 (對接 Transactions 表)
@app.get("/api/transactions/{account_id}")
def get_history(account_id: int):
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            # 注意：新資料表欄位是 TransactionType
            sql = """
            SELECT t.TransactionDate, t.StockSymbol, s.CompanyName, 
                   t.TransactionType, t.Quantity, t.Price, t.Fee, t.Tax
            FROM Transactions t
            JOIN Stocks s ON t.StockSymbol = s.StockSymbol
            WHERE t.AccountID = ?
            ORDER BY t.TransactionDate DESC
            """
            cursor.execute(sql, account_id)
            rows = cursor.fetchall()
            
            history = []
            for row in rows:
                history.append({
                    "transaction_date": row.TransactionDate,
                    "stock_symbol": row.StockSymbol,
                    "company_name": row.CompanyName,
                    "transaction_type": row.TransactionType, # 這裡現在是 BUY/SELL
                    "quantity": row.Quantity,
                    "price": float(row.Price),
                    "fee": float(row.Fee),
                    "tax": float(row.Tax)
                })
            return history
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 3. 買入/賣出 (呼叫更新後的 SP)
@app.post("/api/transaction/{type}")
def execute_trade(type: str, order: TradeRequest):
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            sp_name = "sp_ExecuteBuyOrder" if type == "buy" else "sp_ExecuteSellOrder"
            
            sql = f"EXEC {sp_name} @AccountID=?, @StockSymbol=?, @Quantity=?, @Price=?"
            cursor.execute(sql, order.account_id, order.stock_symbol, order.quantity, order.price)
            conn.commit()
            
            return {"message": "交易成功"}
    except pyodbc.Error as e:
        # 捕捉 SQL 錯誤 (例如餘額不足)
        error_msg = str(e)
        detail = "交易失敗"
        if "50001" in error_msg: detail = "餘額不足 (含手續費)"
        if "50003" in error_msg: detail = "持股不足"
        raise HTTPException(status_code=400, detail=detail)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ==========================================
# 交易 API
# ==========================================

@app.post("/api/transaction/buy", tags=["交易"])
def buy_stock(order: BuyRequest):
    """買入股票"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            # 呼叫買入預存程序
            sql = """
            EXEC sp_ExecuteBuyOrder 
                @AccountID = ?, 
                @StockSymbol = ?, 
                @Quantity = ?, 
                @Price = ?
            """
            
            cursor.execute(sql, 
                         order.account_id, 
                         order.stock_symbol, 
                         order.quantity, 
                         order.price)
            conn.commit()
            
            return {
                "status": "success",
                "message": f"成功買入 {order.stock_symbol} {order.quantity} 股",
                "details": {
                    "stock": order.stock_symbol,
                    "quantity": order.quantity,
                    "price": order.price,
                    "total_cost": order.quantity * order.price
                }
            }
            
    except pyodbc.Error as e:
        error_msg = str(e)
        if "50001" in error_msg:
            raise HTTPException(status_code=400, detail="餘額不足，無法完成交易")
        elif "50002" in error_msg:
            raise HTTPException(status_code=404, detail="股票代碼不存在")
        else:
            raise HTTPException(status_code=400, detail=f"交易失敗: {error_msg}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"系統錯誤: {str(e)}")

@app.post("/api/transaction/sell", tags=["交易"])
def sell_stock(order: SellRequest):
    """賣出股票"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            # 呼叫賣出預存程序
            sql = """
            EXEC sp_ExecuteSellOrder 
                @AccountID = ?, 
                @StockSymbol = ?, 
                @Quantity = ?, 
                @Price = ?
            """
            
            cursor.execute(sql, 
                         order.account_id, 
                         order.stock_symbol, 
                         order.quantity, 
                         order.price)
            conn.commit()
            
            return {
                "status": "success",
                "message": f"成功賣出 {order.stock_symbol} {order.quantity} 股",
                "details": {
                    "stock": order.stock_symbol,
                    "quantity": order.quantity,
                    "price": order.price,
                    "revenue": order.quantity * order.price
                }
            }
            
    except pyodbc.Error as e:
        error_msg = str(e)
        if "50003" in error_msg:
            raise HTTPException(status_code=400, detail="持股不足，無法完成交易")
        else:
            raise HTTPException(status_code=400, detail=f"交易失敗: {error_msg}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"系統錯誤: {str(e)}")

# ==========================================
# 持股查詢 API
# ==========================================

@app.get("/api/holdings/{account_id}", response_model=List[HoldingItem], tags=["持股"])
def get_holdings(account_id: int):
    """查詢帳戶持股"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            sql = """
            SELECT 
                股票代碼, 公司名稱, 持股數量, 平均成本, 
                現價, 市值, 總損益, 報酬率
            FROM vw_CurrentHoldings
            WHERE AccountID = ?
            ORDER BY 市值 DESC
            """
            
            cursor.execute(sql, account_id)
            rows = cursor.fetchall()
            
            results = []
            for row in rows:
                results.append({
                    "stock_symbol": row[0],
                    "company_name": row[1],
                    "quantity": row[2],
                    "average_cost": float(row[3]),
                    "current_price": float(row[4]) if row[4] else 0,
                    "market_value": float(row[5]) if row[5] else 0,
                    "total_profit": float(row[6]) if row[6] else 0,
                    "return_rate": float(row[7]) if row[7] else 0
                })
            
            return results
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"查詢失敗: {str(e)}")

# ==========================================
# 帳戶資訊 API
# ==========================================

@app.get("/api/account/{account_id}", response_model=AccountSummary, tags=["帳戶"])
def get_account_summary(account_id: int):
    """查詢帳戶總覽"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            sql = """
            SELECT 
                AccountID, 用戶名稱, 現金餘額, 持股市值, 總資產, 持股檔數
            FROM vw_AccountOverview
            WHERE AccountID = ?
            """
            
            cursor.execute(sql, account_id)
            row = cursor.fetchone()
            
            if not row:
                raise HTTPException(status_code=404, detail="帳戶不存在")
            
            return {
                "account_id": row[0],
                "user_name": row[1],
                "cash_balance": float(row[2]),
                "stock_value": float(row[3]),
                "total_assets": float(row[4]),
                "holdings_count": row[5]
            }
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"查詢失敗: {str(e)}")

# ==========================================
# 交易歷史 API
# ==========================================

@app.get("/api/transactions/{account_id}", response_model=List[TransactionHistory], tags=["交易"])
def get_transaction_history(account_id: int, limit: int = 20):
    """查詢交易歷史"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            sql = """
            SELECT TOP (?)
                TransactionID, 股票代碼, 公司名稱, 交易類型,
                數量, 單價, 手續費, 證交稅, 交易時間
            FROM vw_TransactionHistory
            WHERE AccountID = ?
            ORDER BY 交易時間 DESC
            """
            
            cursor.execute(sql, limit, account_id)
            rows = cursor.fetchall()
            
            results = []
            for row in rows:
                results.append({
                    "transaction_id": row[0],
                    "stock_symbol": row[1],
                    "company_name": row[2],
                    "transaction_type": row[3],
                    "quantity": row[4],
                    "price": float(row[5]),
                    "fee": float(row[6]) if row[6] else 0,
                    "tax": float(row[7]) if row[7] else 0,
                    "transaction_date": row[8]
                })
            
            return results
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"查詢失敗: {str(e)}")

# ==========================================
# 股票資訊 API
# ==========================================

@app.get("/api/stocks", response_model=List[StockInfo], tags=["股票"])
def get_all_stocks():
    """取得所有股票清單"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            sql = """
            SELECT 
                s.StockSymbol, s.CompanyName, s.Sector,
                dp.ClosePrice, dp.TradeDate
            FROM Stocks s
            LEFT JOIN (
                SELECT StockSymbol, ClosePrice, TradeDate,
                       ROW_NUMBER() OVER(PARTITION BY StockSymbol ORDER BY TradeDate DESC) as rn
                FROM DailyPrices
            ) dp ON s.StockSymbol = dp.StockSymbol AND dp.rn = 1
            WHERE s.IsActive = 1
            ORDER BY s.StockSymbol
            """
            
            cursor.execute(sql)
            rows = cursor.fetchall()
            
            results = []
            for row in rows:
                results.append({
                    "stock_symbol": row[0],
                    "company_name": row[1],
                    "sector": row[2],
                    "latest_price": float(row[3]) if row[3] else None,
                    "trade_date": row[4]
                })
            
            return results
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"查詢失敗: {str(e)}")

@app.get("/api/stock/{stock_symbol}", tags=["股票"])
def get_stock_price(stock_symbol: str):
    """查詢單一股票最新價格"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            sql = """
            SELECT TOP 1
                s.StockSymbol, s.CompanyName, s.Sector,
                dp.TradeDate, dp.OpenPrice, dp.HighPrice, 
                dp.LowPrice, dp.ClosePrice, dp.Volume
            FROM Stocks s
            LEFT JOIN DailyPrices dp ON s.StockSymbol = dp.StockSymbol
            WHERE s.StockSymbol = ?
            ORDER BY dp.TradeDate DESC
            """
            
            cursor.execute(sql, stock_symbol)
            row = cursor.fetchone()
            
            if not row:
                raise HTTPException(status_code=404, detail="股票不存在")
            
            return {
                "stock_symbol": row[0],
                "company_name": row[1],
                "sector": row[2],
                "trade_date": row[3],
                "open": float(row[4]) if row[4] else None,
                "high": float(row[5]) if row[5] else None,
                "low": float(row[6]) if row[6] else None,
                "close": float(row[7]) if row[7] else None,
                "volume": int(row[8]) if row[8] else None
            }
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"查詢失敗: {str(e)}")

# ==========================================
# 執行指令
# ==========================================
if __name__ == "__main__":
    import uvicorn
    # ⚠️ 修改這裡：Port 改為 8001 避免衝突
    print("🚀 啟動股票交易系統 API...")
    print("📖 API 文件: http://127.0.0.1:8001/docs") # 注意 Port 是 8001
    uvicorn.run(app, host="0.0.0.0", port=8001)