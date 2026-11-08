import os
import pyodbc
import yfinance as yf
import pandas as pd
from datetime import datetime
import time
import sys

# ==========================================
# 1. 資料庫連線設定 (Mac 修正版)
# ==========================================
print("正在嘗試連線到資料庫...")

# ⚠️ 請在此填入你的資料庫密碼
password = os.environ.get("DB_PASSWORD", "")

# Mac 連線設定 (使用 ODBC Driver 18)
server = 'localhost'      
database = 'StockTradingDB1'
username = 'sa'           

conn_str = (
    f'DRIVER={{ODBC Driver 18 for SQL Server}};'
    f'SERVER={server};'
    f'DATABASE={database};'
    f'UID={username};'
    f'PWD={password};'
    f'TrustServerCertificate=yes;'
)

conn = None
cursor = None

try:
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    print("✓ 資料庫連接成功！準備更新股價與市場資訊...\n")
except Exception as e:
    print(f"\n❌ 連接失敗！程式將停止執行。")
    print(f"錯誤訊息: {e}")
    print("\n請檢查以下幾點：")
    print("1. 密碼是否正確？(如果是 Docker 架設，通常是設定容器時的密碼)")
    print("2. SQL Server (Docker) 是否正在執行？")
    print("3. 是否已執行 `brew install msodbcsql18` 安裝驅動？")
    sys.exit("無法連線至資料庫")

# ==========================================
# 2. 從資料庫撈出「我們要追蹤哪些股票？」
# ==========================================
print("正在讀取追蹤清單...")
try:
    if cursor:
        cursor.execute("SELECT StockSymbol, CompanyName FROM Stocks WHERE IsActive = 1")
        rows = cursor.fetchall()
        
        if not rows:
            print("⚠ 資料庫中沒有股票！請先執行 SQL 插入股票代號。")
            sys.exit()
    else:
        sys.exit("Cursor 未定義")
        
except Exception as e:
    print(f"✗ 讀取股票清單失敗: {e}")
    print("請確認 Stocks 表是否存在且包含 IsActive 欄位")
    if conn: conn.close()
    sys.exit()

# 把資料庫裡的股票代號轉成 yfinance 格式
target_stocks = []
for row in rows:
    symbol = row[0]
    company_name = row[1]
    # 台股補上 .TW，美股直接使用
    if symbol[0].isdigit():
        yf_symbol = f"{symbol}.TW"
    else:
        yf_symbol = symbol
    target_stocks.append((symbol, company_name, yf_symbol))

print(f"目前追蹤 {len(target_stocks)} 檔股票\n")

# ==========================================
# 3. 逐一抓取歷史股價並寫入資料庫（含 Market & Sector）
# ==========================================
success_count = 0
fail_count = 0
update_log = []

for db_symbol, company_name, yf_symbol in target_stocks:
    print(f"正在更新 {db_symbol} {company_name} ({yf_symbol})...", end=" ")
    
    try:
        # A. 使用 yfinance 抓取資料
        ticker = yf.Ticker(yf_symbol)
        
        # 抓取最近 5 天的資料
        df = ticker.history(period="5d", interval="1d")
        
        if df.empty:
            print("⚠ 無資料 (可能休市或代號錯誤)")
            fail_count += 1
            continue
        
        # B. 整理股價資料 - 取最後一筆（最新）
        df = df.reset_index()
        last_date = df['Date'].iloc[-1].strftime('%Y-%m-%d')
        close_price = float(df['Close'].iloc[-1])
        open_price = float(df['Open'].iloc[-1])
        high_price = float(df['High'].iloc[-1])
        low_price = float(df['Low'].iloc[-1])
        volume = int(df['Volume'].iloc[-1])
        
        # C. 取得 Market 和 Sector 資訊
        info = ticker.info
        market = None
        sector = None
        
        # 從 yfinance 的 info 取得市場資訊
        if 'exchange' in info:
            exchange = info['exchange']
            # 根據交易所代碼判斷市場
            if exchange in ['NMS', 'NGM', 'NCM']:  # NASDAQ
                market = 'NASDAQ'
            elif exchange == 'NYQ':  # NYSE
                market = 'NYSE'
            elif exchange == 'TAI':  # Taiwan
                market = 'TWSE'
            else:
                market = exchange
        
        # 取得產業分類
        if 'sector' in info and info['sector']:
            sector = info['sector']
        
        # D. 更新 Stocks 表的 Market 和 Sector
        if market or sector:
            update_stock_query = '''
            UPDATE Stocks
            SET Market = COALESCE(?, Market),
                Sector = COALESCE(?, Sector)
            WHERE StockSymbol = ?
            '''
            cursor.execute(update_stock_query, (market, sector, db_symbol))
        
        # E. 寫入每日股價資料
        query = '''
        MERGE INTO DailyPrices AS target
        USING (
            SELECT 
                ? AS StockSymbol, 
                ? AS TradeDate, 
                ? AS OpenPrice,
                ? AS HighPrice,
                ? AS LowPrice,
                ? AS ClosePrice,
                ? AS Volume
        ) AS source
        ON target.StockSymbol = source.StockSymbol AND target.TradeDate = source.TradeDate
        WHEN MATCHED THEN
            UPDATE SET 
                OpenPrice = source.OpenPrice,
                HighPrice = source.HighPrice,
                LowPrice = source.LowPrice,
                ClosePrice = source.ClosePrice,
                Volume = source.Volume
        WHEN NOT MATCHED THEN
            INSERT (StockSymbol, TradeDate, OpenPrice, HighPrice, LowPrice, ClosePrice, Volume)
            VALUES (source.StockSymbol, source.TradeDate, source.OpenPrice, source.HighPrice, 
                    source.LowPrice, source.ClosePrice, source.Volume);
        '''
        
        cursor.execute(query, (db_symbol, last_date, open_price, high_price, low_price, close_price, volume))
        conn.commit()
        
        success_count += 1
        update_log.append({
            'symbol': db_symbol,
            'name': company_name,
            'date': last_date,
            'close': close_price,
            'volume': f'{volume:,}',
            'market': market or 'N/A',
            'sector': sector or 'N/A',
            'status': '✓'
        })
        
        market_info = f"市場: {market or 'N/A'}, 產業: {sector or 'N/A'}"
        print(f"✓ 成功! 日期: {last_date}, 收盤: ${close_price:,.2f}, {market_info}")
        time.sleep(0.3)
        
    except Exception as e:
        fail_count += 1
        update_log.append({
            'symbol': db_symbol,
            'name': company_name,
            'date': '',
            'close': 0,
            'volume': '',
            'market': '',
            'sector': '',
            'status': f'✗ {str(e)[:30]}'
        })
        print(f"✗ 失敗: {e}")

# ==========================================
# 4. 顯示結果摘要
# ==========================================
print("\n" + "="*80)
print(f"更新完成 - 成功: {success_count} / 失敗: {fail_count}")
print("="*80)

# 顯示更新摘要表格
if update_log:
    print("\n更新詳細資料：")
    print(f"{'代號':<8} {'公司名稱':<15} {'日期':<12} {'收盤價':<12} {'市場':<10} {'產業':<20} {'狀態'}")
    print("-" * 80)
    for log in update_log:
        if log['status'] == '✓':
            print(f"{log['symbol']:<8} {log['name']:<15} {log['date']:<12} "
                  f"${log['close']:>10,.2f} {log['market']:<10} {log['sector']:<20} {log['status']}")

# ==========================================
# 5. 關閉資料庫連線
# ==========================================
if cursor: cursor.close()
if conn: conn.close()
print("\n✓ 資料庫連線已關閉。")