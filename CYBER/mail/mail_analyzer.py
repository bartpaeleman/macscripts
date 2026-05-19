import sys
import os
import json
import hashlib
import re
import logging
import typer
import mailparser
from typing import Optional, List, Dict, Any
from dateutil.parser import parse as parse_date
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

# Add parent dir to path to import common.core
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from common.core import UnifiedSchema, get_logger

app = typer.Typer()
# Force terminal to allow coloring through the pager pipe
console = Console(force_terminal=True)
logger = get_logger("mail_analyzer")

def extract_auth_results(headers: Dict[str, Any]) -> Dict[str, str]:
    auth_results = {"spf": "unknown", "dkim": "unknown", "dmarc": "unknown"}
    auth_header = headers.get("Authentication-Results", "")
    if not auth_header:
        auth_header = headers.get("authentication-results", "")

    if isinstance(auth_header, list):
        auth_header = " ".join(auth_header)

    if auth_header:
        auth_header = auth_header.lower()
        if "spf=pass" in auth_header: auth_results["spf"] = "pass"
        elif "spf=fail" in auth_header: auth_results["spf"] = "fail"

        if "dkim=pass" in auth_header: auth_results["dkim"] = "pass"
        elif "dkim=fail" in auth_header: auth_results["dkim"] = "fail"

        if "dmarc=pass" in auth_header: auth_results["dmarc"] = "pass"
        elif "dmarc=fail" in auth_header: auth_results["dmarc"] = "fail"

    return auth_results

def reconstruct_relay_chain(received_headers: List[str]) -> List[Dict[str, Any]]:
    chain = []
    import socket
    for i, header in enumerate(received_headers):
        ip_match = re.search(r'\[([\d\.]+|[a-fA-F0-9:]+)\]|\(([\d\.]+|[a-fA-F0-9:]+)\)', header)
        ip = ip_match.group(1) or ip_match.group(2) if ip_match else "unknown"

        hostname = "unknown"
        if ip != "unknown":
            try:
                # Basic reverse DNS lookup
                hostname, _, _ = socket.gethostbyaddr(ip)
            except Exception:
                pass

        parts = header.split(";")
        date_str = parts[-1].strip() if len(parts) > 1 else ""
        parsed_date = None
        tz = "unknown"
        if date_str:
            try:
                parsed_date = parse_date(date_str)
                tz = parsed_date.tzinfo.tzname(None) if parsed_date.tzinfo else "unknown"
            except Exception:
                pass

        chain.append({
            "hop": i + 1,
            "raw": header,
            "ip": ip,
            "hostname": hostname,
            "date": parsed_date.isoformat() if parsed_date else None,
            "timezone": tz
        })

    chain.reverse()
    for i in range(1, len(chain)):
        prev = chain[i-1]
        curr = chain[i]
        if prev["date"] and curr["date"]:
            try:
                d1 = parse_date(prev["date"])
                d2 = parse_date(curr["date"])
                curr["delay_seconds"] = (d2 - d1).total_seconds()
            except Exception:
                curr["delay_seconds"] = None
    chain.reverse()
    return chain

def extract_urls(mail: mailparser.MailParser) -> List[Dict[str, str]]:
    urls = []
    seen = set()

    # Try to extract href and inner text from HTML bodies
    if mail.text_html:
        for t in mail.text_html:
            # Simple regex to find <a href="url">text</a>
            # Note: This is a basic parser and might not catch highly obfuscated HTML
            for match in re.finditer(r'<a\s+(?:[^>]*?\s+)?href=["\'](.*?)["\'][^>]*>(.*?)</a>', t, re.IGNORECASE | re.DOTALL):
                url = match.group(1).strip()
                # Strip internal tags from display text
                text = re.sub(r'<[^>]+>', '', match.group(2)).strip()
                if not text:
                    text = "[No Text/Image]"

                if url not in seen:
                    seen.add(url)
                    urls.append({"url": url, "text": text})

    # Fallback to plain regex for plain text or anything missed
    url_pattern = re.compile(r'https?://[^\s<>"\']+|www\.[^\s<>"\']+')
    texts_to_search = []
    if mail.body: texts_to_search.append(mail.body)
    if mail.text_plain: texts_to_search.extend(mail.text_plain)

    for t in texts_to_search:
        for url in url_pattern.findall(t):
            if url not in seen:
                seen.add(url)
                urls.append({"url": url, "text": url}) # Raw text is just the URL itself

    return urls

@app.command()
def analyze(
    file: str = typer.Argument(..., help="Path to the .eml file or raw headers"),
    json_output: bool = typer.Option(False, "--json", help="Output strict Unified JSON Schema")
):
    """
    Phishing Email Analyzer and Header Trace Engine.
    """
    if not os.path.exists(file):
        if not json_output:
            logger.error(f"File not found: {file}")
        sys.exit(1)

    if json_output:
        logger.setLevel(logging.CRITICAL)

    try:
        mail = mailparser.parse_from_file(file)
    except Exception as e:
        if not json_output:
            logger.error(f"Failed to parse email: {e}")
        sys.exit(1)

    headers = mail.headers

    # Extract headers
    sender = mail.from_
    from_email = sender[0][1] if sender and len(sender) > 0 else "unknown"
    from_name = sender[0][0] if sender and len(sender) > 0 else ""

    return_path = headers.get("Return-Path", "")
    if isinstance(return_path, list): return_path = return_path[0]
    return_path = return_path.strip("<>")

    reply_to = mail.reply_to
    reply_to_email = reply_to[0][1] if reply_to and len(reply_to) > 0 else ""

    auth_results = extract_auth_results(headers)

    received = headers.get("Received", [])
    if isinstance(received, str): received = [received]
    relay_chain = reconstruct_relay_chain(received)

    originating_ip = relay_chain[-1]["ip"] if relay_chain else "unknown"

    # Quick WHOIS lookup on sender domain
    whois_data = {}
    if from_email and "@" in from_email:
        domain = from_email.split("@")[1].lower()
        try:
            import subprocess
            proc = subprocess.run(["whois", domain], capture_output=True, text=True, timeout=5)
            if proc.returncode == 0:
                registrar = ""
                creation_date = ""
                contact = ""
                for line in proc.stdout.splitlines():
                    if "Registrar:" in line and not registrar:
                        registrar = line.split(":", 1)[1].strip()
                    if "Creation Date:" in line and not creation_date:
                        creation_date = line.split(":", 1)[1].strip()
                    if "Registrant Organization:" in line and not contact:
                        contact = line.split(":", 1)[1].strip()
                if registrar or creation_date or contact:
                    whois_data = {"registrar": registrar, "creation_date": creation_date, "contact": contact}
        except Exception as e:
            pass

    anomalies = []
    if return_path and from_email.lower() != return_path.lower():
        anomalies.append(f"Return-Path mismatch: From ({from_email}) vs Return-Path ({return_path})")

    if reply_to_email and from_email.lower() != reply_to_email.lower():
        anomalies.append(f"Reply-To mismatch: From ({from_email}) vs Reply-To ({reply_to_email})")

    if from_name and "@" in from_name and from_name.lower() != from_email.lower():
        anomalies.append(f"Display-name spoofing: Email in display name ({from_name}) differs from actual email ({from_email})")

    timezones = [hop["timezone"] for hop in relay_chain if hop["timezone"] != "unknown"]
    if len(set(timezones)) > 2:
        anomalies.append(f"Suspicious timezone jumps: {timezones}")

    urls = extract_urls(mail)

    attachments = []
    for att in mail.attachments:
        payload = att.get("payload", "")
        try:
            import base64
            raw_bytes = base64.b64decode(payload)
            sha256 = hashlib.sha256(raw_bytes).hexdigest()
        except:
            sha256 = "unknown"

        attachments.append({
            "filename": att.get("filename", "unknown"),
            "content_type": att.get("mail_content_type", "unknown"),
            "sha256": sha256
        })

    # Determine Dangerous Attachments
    dangerous_extensions = ['.exe', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.zip', '.rar', '.js', '.vbs', '.scr']
    has_dangerous_attachment = False
    for att in attachments:
        ext = os.path.splitext(att["filename"].lower())[1]
        if ext in dangerous_extensions:
            has_dangerous_attachment = True
            break

    risk_score = 0
    reasons = []

    if anomalies:
        for a in anomalies:
            if "Return-Path mismatch" in a or "Reply-To mismatch" in a or "Display-name spoofing" in a:
                risk_score += 10
                reasons.append(a + " (+10)")
            else:
                risk_score += 10
                reasons.append(a + " (+10)")

    if reply_to_email == "":
        risk_score += 10
        reasons.append("Reply-To header is empty (+10)")

    for check in ["spf", "dkim", "dmarc"]:
        res = auth_results.get(check, "unknown")
        if res in ["fail", "unknown", "none"]:
            risk_score += 10
            reasons.append(f"{check.upper()} record is {res} (+10)")

    if whois_data and whois_data.get("creation_date"):
        try:
            import datetime as dt
            creation_date = parse_date(whois_data["creation_date"]).replace(tzinfo=dt.timezone.utc)
            age_days = (dt.datetime.now(dt.timezone.utc) - creation_date).days
            if age_days < 14:
                risk_score += 20
                reasons.append(f"WHOIS Creation Date is < 2 weeks ago ({age_days} days) (+20)")
        except Exception:
            pass

    if urls:
        risk_score += 10
        reasons.append(f"Email contains clickable URLs (+10)")

    if has_dangerous_attachment:
        risk_score += 20
        reasons.append("Email contains a potentially dangerous attachment (+20)")

    schema = UnifiedSchema(
        target=from_email,
        risk_score=min(100, risk_score),
        risk_reasons=reasons,
        mail={
            "headers": {
                "from": from_email,
                "return_path": return_path,
                "reply_to": reply_to_email,
                "subject": mail.subject
            },
            "auth": auth_results,
            "relay_chain": relay_chain,
            "anomalies": anomalies
        },
        ioc={
            "urls": urls,
            "attachments": attachments,
            "originating_ip": originating_ip,
            "whois": whois_data
        }
    )

    if json_output:
        print(schema.model_dump_json())
    else:
        # Determine risk label and color
        if schema.risk_score <= 20:
            risk_label = "Low"
            risk_color = "green"
        elif schema.risk_score <= 50:
            risk_label = "Medium"
            risk_color = "yellow"
        elif schema.risk_score <= 80:
            risk_label = "High"
            risk_color = "red"
        else:
            risk_label = "Critical"
            risk_color = "bold red"

        # Ensure LESS allows raw control characters for coloring
        os.environ["LESS"] = "-R"

        # Use console pager to prevent scrolling off the screen
        with console.pager(styles=True):
            console.print(Panel(f"[bold blue]Phishing Email Analysis:[/bold blue] {mail.subject}", expand=False))
            console.print(f"[bold]Target (Sender):[/bold] {from_email}")
            console.print(f"[bold]Risk Score:[/bold] [{risk_color}]{schema.risk_score} ({risk_label})[/{risk_color}]")

            if whois_data:
                console.print(f"\n[bold]Sender Domain WHOIS ({from_email.split('@')[1]}):[/bold]")
                console.print(f"  Registrar: {whois_data.get('registrar', 'unknown')}")
                console.print(f"  Creation Date: {whois_data.get('creation_date', 'unknown')}")
                console.print(f"  Contact: {whois_data.get('contact', 'unknown')}")

            console.print("\n[bold]Authentication Results:[/bold]")
            for k, v in auth_results.items():
                color = "green" if v == "pass" else "red" if v == "fail" else "yellow"
                console.print(f"  {k.upper()}: [{color}]{v}[/{color}]")

            if anomalies:
                console.print("\n[bold red]Anomalies Detected:[/bold red]")
                for a in anomalies:
                    console.print(f"  - {a}")

            if urls:
                console.print(f"\n[bold]Extracted URLs ({len(urls)}):[/bold]")
                url_table = Table(show_header=True, header_style="bold magenta")
                url_table.add_column("Display Text")
                url_table.add_column("Actual Link")

                # Show up to 10 urls to avoid completely filling the screen even with pager
                for u in urls[:10]:
                    url_table.add_row(u["text"][:50] + ("..." if len(u["text"]) > 50 else ""), u["url"])
                console.print(url_table)
                if len(urls) > 10:
                    console.print(f"  ... and {len(urls) - 10} more")

            if attachments:
                console.print(f"\n[bold]Attachments ({len(attachments)}):[/bold]")
                table = Table(show_header=True, header_style="bold magenta")
                table.add_column("Filename")
                table.add_column("SHA256")
                for att in attachments:
                    table.add_row(att["filename"], att["sha256"])
                console.print(table)

            console.print("\n[bold]Relay Chain (Hop-by-Hop):[/bold]")
            chain_table = Table(show_header=True, header_style="bold cyan")
            chain_table.add_column("Hop")
            chain_table.add_column("IP")
            chain_table.add_column("Resolved Hostname")
            chain_table.add_column("Date")
            chain_table.add_column("Delay (s)")
            for hop in relay_chain:
                delay = str(hop.get("delay_seconds", ""))
                chain_table.add_row(str(hop["hop"]), hop["ip"], hop.get("hostname", "unknown"), hop.get("date", ""), delay)
            console.print(chain_table)

        # Prompt user to generate PDF
        console.print("\n[bold cyan]Would you like to export this analysis as a PDF? (y/n):[/bold cyan] ", end="")
        try:
            choice = input().strip().lower()
            if choice == "y" or choice == "yes":
                import subprocess
                reporter_script = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "reporting", "reporter.py"))
                python_bin = sys.executable

                # Construct absolute path in the same dir as the email file
                eml_abspath = os.path.abspath(file)
                eml_dir = os.path.dirname(eml_abspath)
                eml_basename = os.path.basename(eml_abspath)
                pdf_out_path = os.path.join(eml_dir, f"Analyse - {eml_basename}.pdf")

                console.print(f"[yellow]Generating PDF at: {pdf_out_path}...[/yellow]")

                # Execute reporter script with the generated schema JSON payload and --out flag
                proc = subprocess.Popen([python_bin, reporter_script, "--format", "pdf", "--out", pdf_out_path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                stdout, stderr = proc.communicate(input=schema.model_dump_json())

                if proc.returncode == 0:
                    console.print("[bold green]PDF generation completed.[/bold green]")
                else:
                    console.print(f"[bold red]Failed to generate PDF: {stderr}[/bold red]")
        except KeyboardInterrupt:
            pass
        except Exception as e:
            console.print(f"[bold red]Error prompting for PDF: {e}[/bold red]")

if __name__ == "__main__":
    app()
