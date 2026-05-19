import sys
import os
import subprocess
import re

def get_db_stats(host, user, db_name):
    password = os.environ.get('DB_PASS', '')
    # SQL query to get table sizes
    sql = f"""
    SELECT
        table_name AS "Table",
        ROUND(((data_length + index_length) / 1024 / 1024), 2) AS "Size (MB)",
        table_rows AS "Rows"
    FROM information_schema.TABLES
    WHERE table_schema = "{db_name}"
    ORDER BY (data_length + index_length) DESC;
    """

    # Construct command (using mysql CLI to avoid dependencies)
    cmd = ["mysql", "-h", host, "-u", user, f"-p{password}", "-e", sql, "-t"]

    # If host is localhost or 127.0.0.1, QNAP might need explicit socket or TCP
    # Since we don't know socket path, stick to what's passed, but handle error gracefully

    print(f"\n--- Statistics for {db_name} ---")
    try:
        # Suppress password warning
        result = subprocess.run(cmd, check=True, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        print("Error: Could not connect to database or query failed.")
        print("Check your credentials and host.")
    except FileNotFoundError:
        print("Error: 'mysql' command not found.")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 db_stats.py <host> <user> <db_name>")
        print("Note: DB_PASS must be set as an environment variable.")
        sys.exit(1)

    get_db_stats(sys.argv[1], sys.argv[2], sys.argv[3])
