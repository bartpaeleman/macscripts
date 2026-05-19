import sys
import os
import json
import asyncio
import httpx
import ssl
import typer
import tldextract
from datetime import datetime
from typing import Optional, Dict, Any

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from common.core import UnifiedSchema, load_config, get_logger

app = typer.Typer()
logger = get_logger("enricher")
config = load_config()

async def get_asn_hosting(target: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    """Retrieve ASN and ISP info."""
    try:
        # Using ip-api which accepts domains/IPs
        resp = await client.get(f"http://ip-api.com/json/{target}?fields=status,message,countryCode,isp,org,as,query")
        data = resp.json()
        if data.get("status") == "success":
            return {
                "ip": data.get("query"),
                "asn": data.get("as"),
                "isp": data.get("isp"),
                "org": data.get("org"),
                "country": data.get("countryCode")
            }
        else:
            logger.warning(f"ASN Lookup failed for {target}: {data.get('message')}")
    except Exception as e:
        logger.error(f"Error fetching ASN: {e}")
    return {}

async def get_whois_and_rdns(target: str) -> Dict[str, Any]:
    """Retrieve basic WHOIS and Reverse DNS via subprocess."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "whois", target,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, _ = await proc.communicate()
        if proc.returncode == 0:
            output = stdout.decode('utf-8', errors='ignore')
            # Very basic extraction just as an example
            registrar = ""
            creation_date = ""
            contact = ""
            for line in output.splitlines():
                if "Registrar:" in line and not registrar:
                    registrar = line.split(":", 1)[1].strip()
                if "Creation Date:" in line and not creation_date:
                    creation_date = line.split(":", 1)[1].strip()
                if "Registrant Organization:" in line and not contact:
                    contact = line.split(":", 1)[1].strip()
            whois_data = {"registrar": registrar, "creation_date": creation_date, "contact": contact}
        else:
            whois_data = {}

        # Reverse DNS lookup
        rdns = ""
        proc_host = await asyncio.create_subprocess_exec(
            "host", target,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout_host, _ = await proc_host.communicate()
        if proc_host.returncode == 0:
            output_host = stdout_host.decode('utf-8', errors='ignore')
            for line in output_host.splitlines():
                if "domain name pointer" in line:
                    rdns = line.split("domain name pointer")[1].strip()

        return {"whois": whois_data, "rdns": rdns}
    except Exception as e:
        logger.error(f"Error running WHOIS/RDNS: {e}")
    return {}

async def check_abuseipdb(target: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    """Check AbuseIPDB API."""
    api_key = config.get("ABUSEIPDB_API_KEY")
    if not api_key:
        return {}
    try:
        # Note: AbuseIPDB strictly expects IPs. We'll attempt it; if target is domain, it'll fail cleanly via API.
        headers = {
            'Accept': 'application/json',
            'Key': api_key
        }
        resp = await client.get(f"https://api.abuseipdb.com/api/v2/check", params={'ipAddress': target}, headers=headers)
        if resp.status_code == 200:
            data = resp.json()
            return {
                "abuse_score": data["data"]["abuseConfidenceScore"],
                "total_reports": data["data"]["totalReports"]
            }
    except Exception as e:
        logger.error(f"Error checking AbuseIPDB: {e}")
    return {}

async def check_virustotal(target: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    """Check VirusTotal API."""
    api_key = config.get("VT_API_KEY")
    if not api_key:
        return {}
    try:
        headers = {"x-apikey": api_key}
        # Attempt domain lookup
        resp = await client.get(f"https://www.virustotal.com/api/v3/domains/{target}", headers=headers)
        if resp.status_code == 200:
            stats = resp.json().get("data", {}).get("attributes", {}).get("last_analysis_stats", {})
            return {"vt_stats": stats}

        # Fallback to IP address if domain lookup fails
        resp = await client.get(f"https://www.virustotal.com/api/v3/ip_addresses/{target}", headers=headers)
        if resp.status_code == 200:
            stats = resp.json().get("data", {}).get("attributes", {}).get("last_analysis_stats", {})
            return {"vt_stats": stats}
    except Exception as e:
        logger.error(f"Error checking VirusTotal: {e}")
    return {}

async def check_shodan(target: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    """Check Shodan API for open ports and services."""
    api_key = config.get("SHODAN_API_KEY")
    if not api_key:
        return {}

    # Simple check to see if target looks like an IP
    import ipaddress
    try:
        ipaddress.ip_address(target)
    except ValueError:
        # Shodan host lookup requires an IP. If it's a domain, we skip or could resolve it first.
        # For simplicity, we skip if it's not a direct IP.
        return {}

    try:
        resp = await client.get(f"https://api.shodan.io/shodan/host/{target}?key={api_key}")
        if resp.status_code == 200:
            data = resp.json()
            return {
                "ports": data.get("ports", []),
                "vulns": data.get("vulns", []),
                "os": data.get("os", "unknown"),
                "hostnames": data.get("hostnames", [])
            }
        elif resp.status_code == 404:
            return {"status": "Not found in Shodan"}
    except Exception as e:
        logger.error(f"Error checking Shodan: {e}")
    return {}

async def get_tls_info(target: str) -> Dict[str, Any]:
    """Retrieve TLS certificate info."""
    ext = tldextract.extract(target)
    # Target must be a domain
    if not ext.suffix:
        return {}

    try:
        # We run this in a thread because python ssl library is blocking
        loop = asyncio.get_event_loop()
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        from cryptography import x509
        from cryptography.hazmat.backends import default_backend
        import datetime as dt

        def fetch_cert():
            with ssl.create_connection((target, 443), timeout=5) as sock:
                with ctx.wrap_socket(sock, server_hostname=target) as ssock:
                    return ssock.getpeercert(binary_form=True)

        der_cert = await loop.run_in_executor(None, fetch_cert)

        if not der_cert:
            return {}

        cert = x509.load_der_x509_certificate(der_cert, default_backend())

        issuer = cert.issuer.rfc4514_string()
        not_after = cert.not_valid_after_utc

        # Calculate expiry
        age_days = (not_after - dt.datetime.now(dt.timezone.utc)).days

        return {
            "issuer": issuer,
            "not_after": not_after.isoformat(),
            "days_until_expiry": age_days
        }

    except Exception as e:
        logger.warning(f"TLS check failed for {target}: {e}")
    return {}

async def enrich(schema: UnifiedSchema):
    """Run all enrichments concurrently and update the schema."""
    target = schema.target

    # Strip URL protocols to get raw domain/IP
    if target.startswith("http://"): target = target[7:]
    if target.startswith("https://"): target = target[8:]
    target = target.split("/")[0]

    logger.info(f"Starting enrichment for: {target}")

    # Use tldextract
    ext = tldextract.extract(target)
    domain_info = {
        "subdomain": ext.subdomain,
        "domain": ext.domain,
        "suffix": ext.suffix,
        "is_ip": not bool(ext.suffix)
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        # Run enrichments concurrently
        results = await asyncio.gather(
            get_asn_hosting(target, client),
            get_whois_and_rdns(target),
            check_abuseipdb(target, client),
            check_virustotal(target, client),
            get_tls_info(target),
            check_shodan(target, client),
            return_exceptions=True
        )

    asn_data, whois_rdns_data, abuse_data, vt_data, tls_data, shodan_data = [
        res if not isinstance(res, Exception) else {} for res in results
    ]

    # Update Schema
    if not schema.asn: schema.asn = {}
    schema.asn.update(asn_data)

    if not schema.tls: schema.tls = {}
    schema.tls.update(tls_data)

    if not schema.ioc: schema.ioc = {}
    schema.ioc.update({
        "whois": whois_rdns_data.get("whois", {}),
        "rdns": whois_rdns_data.get("rdns", ""),
        "abuseipdb": abuse_data,
        "virustotal": vt_data,
        "shodan": shodan_data,
        "domain_info": domain_info
    })

    # Calculate simple risk score bump
    if abuse_data.get("abuse_score", 0) > 50:
        schema.risk_score += 30
    if vt_data.get("vt_stats", {}).get("malicious", 0) > 0:
        schema.risk_score += 50
    if tls_data.get("days_until_expiry", 999) < 0:
        schema.risk_score += 10 # expired cert

    # Output modified schema strictly to stdout
    print(schema.model_dump_json())


@app.command()
def main(
    target: Optional[str] = typer.Argument(None, help="Target IP, domain, or URL to enrich"),
):
    """
    Passive DNS & URL Enricher.
    Reads from CLI argument or stdin (UnifiedSchema JSON pipeline).
    """
    schema = None

    # Attempt to read from stdin if it's a pipe
    if not sys.stdin.isatty():
        try:
            stdin_data = sys.stdin.read().strip()
            if stdin_data:
                data = json.loads(stdin_data)
                schema = UnifiedSchema(**data)
        except Exception as e:
            logger.error(f"Failed to parse stdin as JSON: {e}")
            sys.exit(1)

    # If no stdin, use target arg
    if not schema:
        if not target:
            logger.error("Must provide a target argument or pipe JSON into stdin.")
            sys.exit(1)
        schema = UnifiedSchema(target=target)

    asyncio.run(enrich(schema))

if __name__ == "__main__":
    app()
