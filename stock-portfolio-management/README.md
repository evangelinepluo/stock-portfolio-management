# Stock Portfolio Management System | 個人理財與股票投資組合管理系統

A personal full-stack coursework project built with **Python, FastAPI, Microsoft SQL Server, HTML, CSS and JavaScript**, featuring portfolio views, transaction workflows, and stock-data synchronization.

> **Portfolio / educational project.** The code is shared to demonstrate database design, API development, and system integration. It is not a real brokerage service and should not be used for actual financial transactions.

## Features | 核心功能

- Account dashboard: cash balance, stock value, and total assets
- Portfolio holdings, profit/loss, and transaction history
- Simulated buy/sell trading workflows with SQL stored procedures
- Financial data synchronization using Python and `yfinance`
- SQL Server schema with foreign keys, views, procedures and triggers
- Responsive browser interface built with HTML/CSS/JavaScript

## Tech Stack

| Layer | Technologies |
| --- | --- |
| Frontend | HTML, CSS, JavaScript |
| Backend | Python, FastAPI, Pydantic, pyodbc |
| Database | Microsoft SQL Server, T-SQL |
| Data pipeline | Python, pandas, yfinance |

## Project Structure

```text
stock-portfolio-management/
├── README.md
├── index.html                # Browser dashboard
├── main.py                   # FastAPI server
├── database.py               # Market-data ETL script
├── requirements.txt
├── .env.example
├── .gitignore
└── sql/
    ├── 01_schema.sql
    ├── 02_sample_data.sql
    ├── 03_procedures_views.sql
    └── 04_triggers_review_required.sql
```

## Local Setup | 本機執行

1. Install Python 3.10+ (suggested), Microsoft SQL Server, and Microsoft ODBC Driver 18 for SQL Server.
2. Create a local SQL Server database named `StockTradingDB1` (or modify the connection strings for your database).
3. Run `sql/01_schema.sql`, then `sql/02_sample_data.sql`, then `sql/03_procedures_views.sql` in SQL Server Management Studio or a compatible T-SQL client. **Do not execute `04_triggers_review_required.sql` before resolving the duplicate holdings-update logic described below.**
4. Install Python dependencies:

   ```bash
   python -m pip install -r requirements.txt
   ```

5. Provide the SQL Server password privately through an environment variable (never commit it):

   ```bash
   export DB_PASSWORD='YOUR_LOCAL_DATABASE_PASSWORD'
   ```

6. Run the API:

   ```bash
   uvicorn main:app --host 127.0.0.1 --port 8001
   ```

7. Open `index.html` in your browser (it calls the local API on port 8001). API docs: <http://127.0.0.1:8001/docs>.
8. Optional: run `python database.py` to sync market data when the database is available. `yfinance` requires internet access.

> These instructions describe the intended development setup. The entire application has **not been end-to-end tested** in this packaged environment. SQL Server, ODBC Driver and network access are needed for a full test.

## Known Issues / Work in Progress | 已知限制

- **Holdings can be updated twice:** `03_procedures_views.sql` updates Holdings inside buy/sell procedures, while `04_triggers_review_required.sql` also updates Holdings after inserting a transaction. Choose one source of truth and test trades before enabling the transaction trigger.
- `main.py` defines some overlapping API routes (including `/health` and transaction history), which should be consolidated.
- This project currently uses a local SQL Server connection; configuration is designed for local demonstration, not production deployment.
- Transaction fees/taxes and market prices are illustrative and require verification before any financial use.
- No automated integration test suite is included yet.
- Local database credentials have been removed from the shared files. Set a new private password using `DB_PASSWORD`.

## My Contribution | 個人負責項目

Independently developed the SQL Server database schema, FastAPI backend, HTML/JavaScript frontend, transaction-related stored procedures and views, and Python-based financial-data update workflow.

## Note

This project uses sample accounts and simulated trades. Never upload actual credentials, personal account information, private database exports, or licensed datasets.
<img width="993" height="549" alt="資料庫前端" src="https://github.com/user-attachments/assets/5a42bb70-79ae-4e49-b79d-f2322bf4e752" />
