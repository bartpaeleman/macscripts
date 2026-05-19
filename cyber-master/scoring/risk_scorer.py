import sys
import os
import json
import typer
from typing import Optional
from datetime import datetime
from dateutil.parser import parse as parse_date

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from common.core import UnifiedSchema, get_logger

app = typer.Typer()
logger = get_logger("risk_scorer")

FINANCIAL_KEYWORDS = ["bank", "login", "secure", "auth", "finance", "crypto", "wallet", "paypal"]
BULLETPROOF_HOSTERS_AND_TOR = ["tor", "bulletproof", "floki", "shinjiru", "koddos", "veesp"]

@app.command()
def analyze():
    """
    Contextual Risk Scoring Engine.
    Reads a UnifiedSchema JSON object from stdin, calculates risk, and outputs to stdout.
    """
    if sys.stdin.isatty():
        logger.error("No input provided. Pipe a Unified JSON object via stdin.")
        sys.exit(1)

    try:
        stdin_data = sys.stdin.read().strip()
        if not stdin_data:
            logger.error("Empty input received.")
            sys.exit(1)
        data = json.loads(stdin_data)
        schema = UnifiedSchema(**data)
    except Exception as e:
        logger.error(f"Failed to parse stdin as JSON or validate schema: {e}")
        sys.exit(1)

    # Initialize scoring
    score = 0
    reasons = []

    # 1. Mail module scoring
    if schema.mail:
        auth = schema.mail.get("auth", {})
        if auth.get("spf") == "fail":
            score += 30
            reasons.append("SPF validation failed (+30)")
        elif auth.get("spf") == "unknown":
            score += 20
            reasons.append("SPF record is missing/unknown (+20)")

        if auth.get("dkim") == "fail":
            score += 30
            reasons.append("DKIM validation failed (+30)")
        elif auth.get("dkim") == "unknown":
            score += 20
            reasons.append("DKIM record is missing/unknown (+20)")

        if auth.get("dmarc") == "none" or auth.get("dmarc") == "unknown":
            # Taking "none" roughly as "not enforced/missing"
            score += 30
            reasons.append("DMARC policy is none/missing (+30)")

        anomalies = schema.mail.get("anomalies", [])
        has_reply_to_anomaly = any("Reply-To mismatch" in a for a in anomalies)
        if has_reply_to_anomaly:
            score += 10
            reasons.append("Suspicious Reply-To mismatch detected (+10)")

        has_reply_empty_anomaly = any("Reply-To header is empty" in a for a in anomalies)
        if has_reply_empty_anomaly:
            score += 10
            reasons.append("Reply-To header is empty (+10)")

        has_return_path_anomaly = any("Return-Path mismatch" in a for a in anomalies)
        if has_return_path_anomaly:
            score += 10
            reasons.append("Suspicious Return-Path mismatch detected (+10)")

        has_spoof_anomaly = any("Display-name spoofing" in a for a in anomalies)
        if has_spoof_anomaly:
            score += 10
            reasons.append("Display-name spoofing detected (+10)")

    if schema.ioc and schema.ioc.get("urls"):
        score += 10
        reasons.append("Email contains clickable URLs (+10)")

    if schema.ioc and schema.ioc.get("attachments"):
        dangerous_extensions = ['.exe', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.zip', '.rar', '.js', '.vbs', '.scr']
        has_dangerous = False
        for att in schema.ioc["attachments"]:
            ext = os.path.splitext(att.get("filename", "").lower())[1]
            if ext in dangerous_extensions:
                has_dangerous = True
                break
        if has_dangerous:
            score += 20
            reasons.append("Email contains a potentially dangerous attachment (+20)")

    # 2. ASN/Enrich module scoring
    if schema.asn:
        asn_desc = str(schema.asn.get("asn", "")).lower()
        isp_desc = str(schema.asn.get("isp", "")).lower()
        org_desc = str(schema.asn.get("org", "")).lower()

        is_bulletproof = any(kw in asn_desc or kw in isp_desc or kw in org_desc for kw in BULLETPROOF_HOSTERS_AND_TOR)
        if is_bulletproof:
            score += 40
            reasons.append("ASN matches known bulletproof hoster or Tor exit node (+40)")

    if schema.ioc and schema.ioc.get("whois"):
        creation_date_str = schema.ioc["whois"].get("creation_date")
        if creation_date_str:
            try:
                import datetime as dt
                creation_date = parse_date(creation_date_str).replace(tzinfo=dt.timezone.utc)
                age_days = (dt.datetime.now(dt.timezone.utc) - creation_date).days
                if age_days < 14:
                    score += 20
                    reasons.append(f"WHOIS Creation Date is < 2 weeks ago ({age_days} days) (+20)")
                elif age_days < 30:
                    score += 20
                    reasons.append(f"Newly registered domain (Age: {age_days} days) (+20)")
            except Exception as e:
                pass

    # 3. TLS module scoring
    if schema.tls:
        issuer = str(schema.tls.get("issuer", "")).lower()
        target_lower = schema.target.lower()

        is_financial_target = any(kw in target_lower for kw in FINANCIAL_KEYWORDS)
        if "let's encrypt" in issuer and is_financial_target:
            score += 20
            reasons.append("Let's Encrypt cert used on a financial/login target (+20)")

        days_until_expiry = schema.tls.get("days_until_expiry")
        if days_until_expiry is not None and days_until_expiry < 0:
            score += 40
            reasons.append("TLS Certificate is expired (+40)")

    # 4. IOC module scoring (VirusTotal)
    if schema.ioc and schema.ioc.get("virustotal"):
        vt_stats = schema.ioc["virustotal"].get("vt_stats", {})
        malicious_hits = vt_stats.get("malicious", 0)
        if malicious_hits > 0:
            vt_score = min(50, malicious_hits * 5)
            score += vt_score
            reasons.append(f"VirusTotal detected {malicious_hits} malicious hits (+{vt_score})")

    # 5. IOC module scoring (Shodan)
    if schema.ioc and schema.ioc.get("shodan"):
        shodan_data = schema.ioc["shodan"]

        # Check for exposed sensitive ports
        exposed_ports = shodan_data.get("ports", [])
        sensitive_ports = {
            21: "FTP", 22: "SSH", 23: "Telnet",
            3306: "MySQL", 5432: "PostgreSQL",
            27017: "MongoDB", 3389: "RDP"
        }

        found_sensitive = [sensitive_ports[p] for p in exposed_ports if p in sensitive_ports]
        if found_sensitive:
            score += 20
            reasons.append(f"Shodan detected exposed sensitive ports: {', '.join(found_sensitive)} (+20)")

        # Check for known vulnerabilities
        vulns = shodan_data.get("vulns", [])
        if vulns:
            score += 30
            reasons.append(f"Shodan detected {len(vulns)} known vulnerabilities (+30)")

    # Finalize score
    schema.risk_score = min(100, score)
    schema.risk_reasons = reasons

    # Output strictly to stdout
    print(schema.model_dump_json())

if __name__ == "__main__":
    app()
