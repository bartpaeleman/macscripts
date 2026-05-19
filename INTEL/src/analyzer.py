#!/usr/bin/env python3
"""
analyzer.py

Parses downloaded Threat Intelligence sources (RSS, JSON),
matches content against defined keywords, and generates a unified HTML report.
"""

import json
import sys
import os
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta

# Fallback for missing 'html' module on QNAP
try:
    import html
    def escape_html(text): return html.escape(text)
    def unescape_html(text): return html.unescape(text)
except ImportError:
    def escape_html(text):
        if not text: return ""
        return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&#x27;")

    def unescape_html(text):
        if not text: return ""
        return str(text).replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&#x27;", "'").replace("&#39;", "'")


class ThreatItem:
    """Represents a single threat intelligence finding."""
    def __init__(self, title, link, date_str, summary, source_name, technologies_found, inclusions_found):
        self.title = title
        self.link = link
        self.date_str = date_str
        self.summary = summary
        self.source_name = source_name
        self.technologies_found = technologies_found
        self.inclusions_found = inclusions_found

class IntelAnalyzer:
    """Core logic to parse sources and generate reports."""
    def __init__(self, config_path, data_dir, output_dir, css_path):
        self.config_path = config_path
        self.data_dir = data_dir
        self.output_dir = output_dir
        self.css_path = css_path
        self.config = self._load_config()
        # Handle transition from 'keywords' to 'technologies'
        self.technologies = [k.lower() for k in self.config.get('technologies', self.config.get('keywords', []))]
        self.exclusions = [e.lower() for e in self.config.get('exclusions', [])]
        self.inclusions = [i.lower() for i in self.config.get('inclusions', [])]
        self.lookback_days = self.config.get('parameters', {}).get('lookback_days', 7)
        self.strict_filtering = self.config.get('parameters', {}).get('strict_filtering', True)
        self.cutoff_date = datetime.now() - timedelta(days=self.lookback_days)
        self.findings = []

        # Apply environment-based filtering if set from script-master
        filter_mode = os.environ.get('INTEL_FILTER', 'default')
        if filter_mode == 'general':
            self.inclusions.extend(['breach', 'attack', 'hacked', 'data leak', 'cyber', 'security'])
            self.exclusions.extend(['patch', 'update', 'cve', 'vulnerability', 'flaw'])
        elif filter_mode == 'patches':
            self.inclusions.extend(['patch', 'update', 'cve', 'vulnerability', 'flaw', 'zero-day', 'exploit', 'rce'])
            # Do NOT clear keywords, append user's keywords so they still filter patches by tech stack
        elif filter_mode == 'other':
            self.inclusions.extend(['malware', 'ransomware', 'phishing', 'apt', 'botnet', 'ddos'])
            self.exclusions.extend(['patch', 'update'])

    def _load_config(self):
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading config: {e}", file=sys.stderr)
            sys.exit(1)

    def _sanitize_html(self, text):
        """Removes HTML tags and converts entities."""
        if not text:
            return ""
        # Unescape entities first to expose hidden tags
        text = unescape_html(text)
        # Then strip all tags
        clean = re.sub(r'<.*?>', '', text)
        return clean.strip()

    def _find_technologies(self, text):
        """Returns list of matched technologies in text."""
        if not text:
            return []
        text_lower = text.lower()
        return [tech for tech in self.technologies if tech.lower() in text_lower]

    def _find_inclusions(self, text):
        """Returns list of matched inclusions in text."""
        if not text:
            return []
        text_lower = text.lower()
        return [inc for inc in self.inclusions if inc.lower() in text_lower]

    def _has_exclusions(self, text):
        """Returns True if any exclusion words are found in the text."""
        if not text or not self.exclusions:
            return False
        text_lower = text.lower()
        return any(ex in text_lower for ex in self.exclusions)

    def _parse_date(self, date_str):
        """Attempts to parse standard date formats."""
        if not date_str:
            return datetime.now()
        # Clean up some common RSS date anomalies
        # e.g., "Tue, 16 Apr 2024 10:00:00 +0000"
        try:
            from dateutil.parser import parse
            return parse(date_str, fuzzy=True).replace(tzinfo=None)
        except ImportError:
            # Fallback if dateutil is not installed (using regex and basic parsing could be done here,
            # but we assume the environment might be minimal. A basic approach is best effort.)
            # For this exercise, we will assume all dates are valid if dateutil isn't there,
            # but we'll try a basic strptime fallback.
            pass

        try:
            # Try basic RSS format
            # e.g. Wed, 02 Oct 2002 13:00:00 GMT
            import email.utils
            parsed = email.utils.parsedate_to_datetime(date_str)
            return parsed.replace(tzinfo=None)
        except Exception:
            return datetime.now()

    def analyze_rss(self, file_path, source_name):
        try:
            tree = ET.parse(file_path)
            root = tree.getroot()

            # Basic RSS
            for item in root.findall('.//item'):
                title = item.findtext('title', '')
                link = item.findtext('link', '')
                pub_date = item.findtext('pubDate', '')
                desc = self._sanitize_html(item.findtext('description', ''))

                content = f"{title} {desc}"
                tech_matches = self._find_technologies(content)
                inc_matches = self._find_inclusions(content)

                # Keep if not strict OR there are inclusions OR (tech matches exist AND no exclusions).
                if not self.strict_filtering or inc_matches or (tech_matches and not self._has_exclusions(content)):
                    dt = self._parse_date(pub_date)
                    if dt >= self.cutoff_date:
                        self.findings.append(ThreatItem(
                            title=title, link=link, date_str=pub_date,
                            summary=desc, source_name=source_name,
                            technologies_found=tech_matches, inclusions_found=inc_matches
                        ))
        except Exception as e:
            # Fallback for malformed XML: attempt naive regex parsing silently
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    xml_content = f.read()

                items = re.findall(r'<item[^>]*>(.*?)</item>', xml_content, re.IGNORECASE | re.DOTALL)
                for item in items:
                    title_match = re.search(r'<title[^>]*>(.*?)</title>', item, re.IGNORECASE | re.DOTALL)
                    link_match = re.search(r'<link[^>]*>(.*?)</link>', item, re.IGNORECASE | re.DOTALL)
                    pub_date_match = re.search(r'<pubDate[^>]*>(.*?)</pubDate>', item, re.IGNORECASE | re.DOTALL)
                    desc_match = re.search(r'<description[^>]*>(.*?)</description>', item, re.IGNORECASE | re.DOTALL)

                    title = self._sanitize_html(title_match.group(1)) if title_match else ''
                    link = link_match.group(1).strip() if link_match else ''
                    pub_date = pub_date_match.group(1).strip() if pub_date_match else ''
                    desc = self._sanitize_html(desc_match.group(1)) if desc_match else ''

                    # Some CDATA sections might need extra sanitization
                    title = re.sub(r'<!\[CDATA\[(.*?)\]\]>', r'\1', title)
                    desc = re.sub(r'<!\[CDATA\[(.*?)\]\]>', r'\1', desc)

                    content = f"{title} {desc}"
                    tech_matches = self._find_technologies(content)
                    inc_matches = self._find_inclusions(content)

                    if not self.strict_filtering or inc_matches or (tech_matches and not self._has_exclusions(content)):
                        dt = self._parse_date(pub_date)
                        if dt >= self.cutoff_date:
                            self.findings.append(ThreatItem(
                                title=title, link=link, date_str=pub_date,
                                summary=desc, source_name=source_name,
                                technologies_found=tech_matches, inclusions_found=inc_matches
                            ))
            except Exception:
                # Silently ignore if fallback fails as well, to prevent console spam
                pass

    def analyze_cisa_kev(self, file_path, source_name):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)

            for vuln in data.get('vulnerabilities', []):
                title = vuln.get('vulnerabilityName', '')
                desc = vuln.get('shortDescription', '')
                date_added = vuln.get('dateAdded', '')
                cve = vuln.get('cveID', '')
                link = f"https://nvd.nist.gov/vuln/detail/{cve}"

                content = f"{title} {desc}"
                tech_matches = self._find_technologies(content)
                inc_matches = self._find_inclusions(content)

                if not self.strict_filtering or inc_matches or (tech_matches and not self._has_exclusions(content)):
                    try:
                        dt = datetime.strptime(date_added, '%Y-%m-%d')
                    except ValueError:
                        dt = datetime.now()

                    if dt >= self.cutoff_date:
                        self.findings.append(ThreatItem(
                            title=title, link=link, date_str=date_added,
                            summary=desc, source_name=source_name,
                            technologies_found=tech_matches, inclusions_found=inc_matches
                        ))
        except Exception as e:
            print(f"Error parsing JSON {file_path}: {e}", file=sys.stderr)

    def analyze_atom(self, file_path, source_name):
        try:
            tree = ET.parse(file_path)
            root = tree.getroot()
            # Atom namespace can be complex, use wildcard for basic tags
            ns = {'atom': 'http://www.w3.org/2005/Atom'}
            entries = root.findall('.//{http://www.w3.org/2005/Atom}entry')
            if not entries:
                 entries = root.findall('.//entry') # fallback without namespace

            for entry in entries:
                title_elem = entry.find('{http://www.w3.org/2005/Atom}title')
                if title_elem is None: title_elem = entry.find('title')
                title = title_elem.text if title_elem is not None else ''

                link = ''
                link_elems = entry.findall('{http://www.w3.org/2005/Atom}link')
                if not link_elems: link_elems = entry.findall('link')
                for l in link_elems:
                    if l.get('rel') == 'alternate' or not l.get('rel'):
                        link = l.get('href', '')
                        break

                updated_elem = entry.find('{http://www.w3.org/2005/Atom}updated')
                if updated_elem is None: updated_elem = entry.find('updated')
                pub_date = updated_elem.text if updated_elem is not None else ''

                content_elem = entry.find('{http://www.w3.org/2005/Atom}content')
                if content_elem is None: content_elem = entry.find('content')
                desc = self._sanitize_html(content_elem.text if content_elem is not None else '')

                if not desc:
                    summary_elem = entry.find('{http://www.w3.org/2005/Atom}summary')
                    if summary_elem is None: summary_elem = entry.find('summary')
                    desc = self._sanitize_html(summary_elem.text if summary_elem is not None else '')

                content = f"{title} {desc}"
                tech_matches = self._find_technologies(content)
                inc_matches = self._find_inclusions(content)

                if inc_matches or (tech_matches and not self._has_exclusions(content)):
                    dt = self._parse_date(pub_date)
                    if dt >= self.cutoff_date:
                        self.findings.append(ThreatItem(
                            title=title, link=link, date_str=pub_date,
                            summary=desc, source_name=source_name,
                            technologies_found=tech_matches, inclusions_found=inc_matches
                        ))
        except Exception as e:
            # Fallback for malformed XML: attempt naive regex parsing silently
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    xml_content = f.read()

                entries = re.findall(r'<entry[^>]*>(.*?)</entry>', xml_content, re.IGNORECASE | re.DOTALL)
                for entry in entries:
                    title_match = re.search(r'<title[^>]*>(.*?)</title>', entry, re.IGNORECASE | re.DOTALL)
                    link_match = re.search(r'<link[^>]*href=[\"\'](.*?)[\"\'][^>]*>', entry, re.IGNORECASE)
                    pub_date_match = re.search(r'<updated[^>]*>(.*?)</updated>', entry, re.IGNORECASE | re.DOTALL)
                    content_match = re.search(r'<content[^>]*>(.*?)</content>', entry, re.IGNORECASE | re.DOTALL)
                    if not content_match:
                        content_match = re.search(r'<summary[^>]*>(.*?)</summary>', entry, re.IGNORECASE | re.DOTALL)

                    title = self._sanitize_html(title_match.group(1)) if title_match else ''
                    link = link_match.group(1).strip() if link_match else ''
                    pub_date = pub_date_match.group(1).strip() if pub_date_match else ''
                    desc = self._sanitize_html(content_match.group(1)) if content_match else ''

                    title = re.sub(r'<!\[CDATA\[(.*?)\]\]>', r'\1', title)
                    desc = re.sub(r'<!\[CDATA\[(.*?)\]\]>', r'\1', desc)

                    content_eval = f"{title} {desc}"
                    tech_matches = self._find_technologies(content_eval)
                    inc_matches = self._find_inclusions(content_eval)

                    if not self.strict_filtering or inc_matches or (tech_matches and not self._has_exclusions(content_eval)):
                        dt = self._parse_date(pub_date)
                        if dt >= self.cutoff_date:
                            self.findings.append(ThreatItem(
                                title=title, link=link, date_str=pub_date,
                                summary=desc, source_name=source_name,
                                technologies_found=tech_matches, inclusions_found=inc_matches
                            ))
            except Exception:
                # Silently ignore if fallback fails as well, to prevent console spam
                pass

    def analyze_html(self, file_path, source_name):
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()

            # Naive HTML extraction: grab titles and links from <a> tags
            a_tags = re.findall(r'<a\s+(?:[^>]*?\s+)?href=(["\'])(.*?)\1[^>]*>(.*?)</a>', content, re.IGNORECASE | re.DOTALL)

            seen_links = set()
            for _, link, text in a_tags:
                if link in seen_links or link.startswith('#') or link.startswith('javascript'):
                    continue
                seen_links.add(link)

                title = self._sanitize_html(text)
                if not title:
                    continue

                # Expand relative links safely if it looks like a relative path
                if link.startswith('/'):
                    # Guess domain from source URL if available in config?
                    # For simplicity, just store the relative link.
                    pass

                full_content = f"{title}"
                tech_matches = self._find_technologies(full_content)
                inc_matches = self._find_inclusions(full_content)

                if not self.strict_filtering or inc_matches or (tech_matches and not self._has_exclusions(full_content)):
                    self.findings.append(ThreatItem(
                        title=title, link=link, date_str=datetime.now().strftime("%Y-%m-%d"),
                        summary="Parsed from HTML feed", source_name=source_name,
                        technologies_found=tech_matches, inclusions_found=inc_matches
                    ))
        except Exception as e:
            print(f"Error parsing HTML {file_path}: {e}", file=sys.stderr)

    def process_all(self):
        """Iterates through downloaded files and delegates to specific parsers."""
        sources = self.config.get('sources', [])
        for i, source in enumerate(sources):
            # Skip inactive sources
            if not source.get('active', True):
                continue

            # The shell script saves files as source_0.raw, source_1.raw, etc.
            raw_file = os.path.join(self.data_dir, f"source_{i}.raw")
            if not os.path.exists(raw_file):
                print(f"Skipping {source['name']}, file not found.", file=sys.stderr)
                continue

            if source.get('type') == 'rss':
                self.analyze_rss(raw_file, source['name'])
            elif source.get('type') == 'cisa_kev':
                self.analyze_cisa_kev(raw_file, source['name'])
            elif source.get('type') == 'atom':
                self.analyze_atom(raw_file, source['name'])
            elif source.get('type') == 'html':
                self.analyze_html(raw_file, source['name'])

    def generate_report(self):
        """Creates the final HTML report."""
        try:
            with open(self.css_path, 'r', encoding='utf-8') as f:
                css_content = f.read()
        except Exception:
            css_content = "/* CSS missing */"

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        file_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_path = os.path.join(self.output_dir, f"intel_report_{file_timestamp}.html")

        # Group findings by source
        grouped_findings = {}
        for item in self.findings:
            if item.source_name not in grouped_findings:
                grouped_findings[item.source_name] = []
            grouped_findings[item.source_name].append(item)

        js_logic = r"""
<script>
function filterReport() {
    let input = document.getElementById('searchFilter').value.toLowerCase();
    let isFuzzy = document.getElementById('fuzzyToggle').checked;
    let isOrCondition = document.getElementById('orToggle').checked;
    let cards = document.getElementsByClassName('threat-card');

    // Split by commas for multiple filters
    let rawFilters = input.split(',').map(s => s.trim()).filter(s => s.length > 0);
    let visibleCount = 0;

    for (let i = 0; i < cards.length; i++) {
        let card = cards[i];
        let text = card.innerText.toLowerCase();
        let summary = card.getAttribute('data-summary').toLowerCase();
        let sourceName = card.getAttribute('data-source').toLowerCase();
        let technologies = card.getAttribute('data-technologies').toLowerCase();
        let inclusions = card.getAttribute('data-inclusions').toLowerCase();

        let hasMatch = false;
        let matchesAll = true;

        if (rawFilters.length === 0) {
            hasMatch = true;
        } else {
            for (let j = 0; j < rawFilters.length; j++) {
                let filterText = rawFilters[j];

                let isSourceFilter = filterText.startsWith('source:');
                let isKeywordFilter = filterText.startsWith('technology:') || filterText.startsWith('technologies:') || filterText.startsWith('keyword:') || filterText.startsWith('keywords:');
                let isInclusionFilter = filterText.startsWith('inclusion:') || filterText.startsWith('inclusions:');
                let searchTerm = filterText;

                if (isSourceFilter) searchTerm = filterText.replace('source:', '').trim();
                else if (isKeywordFilter) searchTerm = filterText.replace(/^(technology|technologies|keyword|keywords):/, '').trim();
                else if (isInclusionFilter) searchTerm = filterText.replace(/^(inclusion|inclusions):/, '').trim();

                if (!searchTerm) {
                    // Empty specific filter string acts like a match to not break AND logic randomly
                    hasMatch = true;
                    continue;
                }

                let match = false;
                let targetText = "";

                if (isSourceFilter) {
                    targetText = sourceName;
                } else if (isKeywordFilter) {
                    targetText = technologies;
                } else if (isInclusionFilter) {
                    targetText = inclusions;
                } else {
                    targetText = text + " " + summary + " " + technologies + " " + inclusions;
                }

                if (isFuzzy && !isSourceFilter && !isKeywordFilter && !isInclusionFilter) {
                    match = fuzzyMatch(searchTerm, targetText);
                } else {
                    // Strict check for prefix filters, loose check for general text
                    match = targetText.includes(searchTerm);
                }

                if (match) {
                    hasMatch = true;
                } else {
                    matchesAll = false;
                }
            }
        }

        let isVisible = isOrCondition ? hasMatch : matchesAll;
        if (input.trim() === '') isVisible = true;

        if (isVisible) {
            card.style.display = '';
            card.classList.add('visible-card');
            visibleCount++;
            // Auto-expand the parent details element if a filter is actively matching it
            if (input.trim() !== '') {
                let parentDetails = card.closest('details');
                if (parentDetails) {
                    parentDetails.open = true;
                }
            }
        } else {
            card.style.display = 'none';
            card.classList.remove('visible-card');
        }
    }

    // Update Total Matches stat
    let matchStat = document.getElementById('totalMatchesStat');
    if (matchStat) matchStat.innerText = visibleCount;

    // Hide empty details blocks
    let detailsBlocks = document.getElementsByClassName('source-section');
    for (let i = 0; i < detailsBlocks.length; i++) {
        let details = detailsBlocks[i];
        let visibleCards = details.querySelectorAll('.visible-card');
        if (visibleCards.length === 0) {
            details.style.display = 'none';
        } else {
            details.style.display = '';
        }
    }
}

function fuzzyMatch(pattern, str) {
    // Splits the input into words and checks if any word in the string
    // is a close match (Levenshtein distance <= 2) to the pattern.
    // Simplification for fast client-side searching.
    let strWords = str.split(/[\s,]+/);
    let patternWords = pattern.split(/[\s,]+/);

    // For each word in the pattern, there must be a word in the string that is close.
    for (let i = 0; i < patternWords.length; i++) {
        let pWord = patternWords[i];
        if (pWord.length < 3) {
            // For very short pattern words, require exact match
            if (!str.includes(pWord)) return false;
            continue;
        }

        let foundMatch = false;
        for (let j = 0; j < strWords.length; j++) {
            let sWord = strWords[j];
            if (Math.abs(pWord.length - sWord.length) > 2) continue;

            let dist = levenshtein(pWord, sWord);
            // Allow 1 typo for words up to 5 chars, 2 typos for longer words
            let maxDist = pWord.length <= 5 ? 1 : 2;
            if (dist <= maxDist) {
                foundMatch = true;
                break;
            }
        }

        if (!foundMatch && !str.includes(pWord)) {
            return false;
        }
    }
    return true;
}

function levenshtein(a, b) {
    if (a.length === 0) return b.length;
    if (b.length === 0) return a.length;

    let matrix = [];
    for (let i = 0; i <= b.length; i++) {
        matrix[i] = [i];
    }
    for (let j = 0; j <= a.length; j++) {
        matrix[0][j] = j;
    }

    for (let i = 1; i <= b.length; i++) {
        for (let j = 1; j <= a.length; j++) {
            if (b.charAt(i-1) == a.charAt(j-1)) {
                matrix[i][j] = matrix[i-1][j-1];
            } else {
                matrix[i][j] = Math.min(matrix[i-1][j-1] + 1, Math.min(matrix[i][j-1] + 1, matrix[i-1][j] + 1));
            }
        }
    }
    return matrix[b.length][a.length];
}

function showDetails(element) {
    let title = element.getAttribute('data-title');
    let date = element.getAttribute('data-date');
    let summary = element.getAttribute('data-summary');
    let link = element.getAttribute('data-link');

    let detailView = document.getElementById('dynamicDetail');
    let detailContent = document.getElementById('detailContent');

    // Prevent XSS by securely setting attributes and text content using DOM APIs
    detailContent.innerHTML = ''; // Clear previous

    let h3 = document.createElement('h3');
    let a = document.createElement('a');
    a.href = link; // Browser securely assigns href attribute
    a.target = '_blank';
    a.innerText = title;
    h3.appendChild(a);
    detailContent.appendChild(h3);

    let dateDiv = document.createElement('div');
    dateDiv.className = 'threat-date';
    dateDiv.innerText = date;
    detailContent.appendChild(dateDiv);

    let summaryDiv = document.createElement('div');
    summaryDiv.className = 'threat-summary';
    // We already sanitized the summary text on the python side and we want our highlight spans to render, so we use innerHTML
    summaryDiv.innerHTML = summary;
    detailContent.appendChild(summaryDiv);

    // Move the detail view directly after the clicked card in the DOM so it spans the grid
    element.parentNode.insertBefore(detailView, element.nextSibling);
    detailView.style.display = 'block';

    // Smooth scroll to the expanded item
    element.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function showFilterModal(type) {
    document.getElementById('filterModal').style.display = 'block';

    document.getElementById('modal-sources').style.display = 'none';
    document.getElementById('modal-technologies').style.display = 'none';
    document.getElementById('modal-inclusions').style.display = 'none';

    document.getElementById('modal-' + type).style.display = 'block';

    let title = "Select a Filter";
    if (type === 'sources') title = "Select Source";
    if (type === 'technologies') title = "Select Technology";
    if (type === 'inclusions') title = "Select Inclusion";

    document.getElementById('filterModalTitle').innerText = title;
}

function selectFilterOption(type, element) {
    let value = element.getAttribute('data-val');
    let prefix = '';

    if(type === 'sources') prefix = 'source:';
    if(type === 'technologies') prefix = 'technology:';
    if(type === 'inclusions') prefix = 'inclusion:';

    let input = document.getElementById('searchFilter');
    let current = input.value.trim();
    let newFilter = prefix + value;

    if (current.length > 0 && !current.endsWith(',')) {
        input.value = current + ', ' + newFilter;
    } else {
        input.value = current + newFilter;
    }

    document.getElementById('filterModal').style.display = 'none';
    input.focus();
    filterReport();
}
</script>
        """

        safe_technologies = escape_html(", ".join(self.technologies)) if self.technologies else "None"
        safe_inclusions = escape_html(", ".join(self.inclusions)) if self.inclusions else "None"
        safe_exclusions = escape_html(", ".join(self.exclusions)) if self.exclusions else "None"
        params = self.config.get('parameters', {})
        min_sev = escape_html(str(params.get('minimum_severity', 'High')))
        lookback = escape_html(str(params.get('lookback_days', 7)))
        strict_val = escape_html(str(params.get('strict_filtering', True)))

        html_out = [
            "<!DOCTYPE html>",
            "<html lang='en'>",
            "<head>",
            "<meta charset='UTF-8'>",
            "<meta name='viewport' content='width=device-width, initial-scale=1.0'>",
            f"<title>Threat Intel Report - {timestamp}</title>",
            f"<style>\n{css_content}\n</style>",
            "</head>",
            "<body>",
            "<div class='container'>",
            "<header>",
            "<div>",
            "<h1>Threat Intelligence Report</h1>",
            f"<div class='timestamp'>Generated: {timestamp}</div>",
            "</div>",
            "<div>",
            "<button onclick='document.getElementById(\"configModal\").style.display=\"block\";' style='padding: 8px 16px; background-color: var(--accent-blue); color: #fff; border: none; border-radius: 4px; cursor: pointer;'>View Config</button>",
            "</div>",
            "</header>",

            "<div class='search-bar' style='margin-bottom: 20px; display:flex; gap: 10px; align-items: center;'>",
            "<input type='text' id='searchFilter' onkeyup='filterReport()' placeholder='Search report contents (e.g. source:The Hacker News, keyword:chrome, inclusion:vulnerability)' style='flex-grow: 1; padding: 10px; font-size: 1.1em; border-radius: 6px; border: 1px solid var(--border-color); background-color: var(--bg-card); color: var(--text-main);'>",
            "<label style='display:flex; align-items:center; gap:5px; cursor:pointer;'><input type='checkbox' id='fuzzyToggle' onchange='filterReport()'> Fuzzy Match</label>",
            "<label style='display:flex; align-items:center; gap:5px; cursor:pointer;' title='Match ANY filter instead of ALL filters'><input type='checkbox' id='orToggle' onchange='filterReport()'> OR Mode</label>",
            "</div>",

            "<div class='dashboard-stats'>",
            f"<div class='stat-card' style='cursor:pointer;' onclick=\"document.getElementById('searchFilter').value=''; filterReport();\"><div class='stat-value'><a href='#' id='totalMatchesStat' style='color:inherit;text-decoration:none;'>{len(self.findings)}</a></div><div class='stat-label'>Total Matches</div></div>",
            f"<div class='stat-card' style='cursor:pointer;' onclick=\"showFilterModal('sources')\"><div class='stat-value'><a href='#' style='color:inherit;text-decoration:none;'>{len(grouped_findings)}</a></div><div class='stat-label'>Active Sources</div></div>",
            f"<div class='stat-card' style='cursor:pointer;' onclick=\"showFilterModal('technologies')\"><div class='stat-value'><a href='#' style='color:inherit;text-decoration:none;'>{len(self.technologies)}</a></div><div class='stat-label'>Monitored Tech</div></div>",
            f"<div class='stat-card' style='cursor:pointer;' onclick=\"showFilterModal('inclusions')\"><div class='stat-value'><a href='#' style='color:inherit;text-decoration:none;'>{len(self.inclusions)}</a></div><div class='stat-label'>Inclusions</div></div>",
            "</div>",

            "<!-- Config Modal -->",
            "<div id='configModal' style='display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.8); z-index:1000;'>",
            "<div style='position:absolute; top:50%; left:50%; transform:translate(-50%, -50%); background:var(--bg-card); padding:30px; border-radius:8px; border:1px solid var(--border-color); min-width:400px; max-width:80%; max-height:80%; overflow-y:auto;'>",
            "<div style='display:flex; justify-content:space-between; border-bottom:1px solid var(--border-color); padding-bottom:10px; margin-bottom:20px;'>",
            "<h2 style='margin:0;'>Active Configuration</h2>",
            "<button onclick='document.getElementById(\"configModal\").style.display=\"none\";' style='background:none; border:none; color:var(--text-muted); cursor:pointer; font-size:1.5em;'>&times;</button>",
            "</div>",
            f"<div><strong>Parameters:</strong><p style='color:var(--text-muted);'>Strict Filtering: {strict_val} | Minimum Severity: {min_sev} | Lookback Days: {lookback}</p></div>",
            f"<div><strong>Technologies:</strong><p style='color:var(--accent-blue); word-wrap:break-word;'>{safe_technologies}</p></div>",
            f"<div><strong>Inclusions:</strong><p style='color:var(--accent-green); word-wrap:break-word;'>{safe_inclusions}</p></div>",
            f"<div><strong>Exclusions:</strong><p style='color:var(--accent-red); word-wrap:break-word;'>{safe_exclusions}</p></div>",
            "</div></div>"
        ]

        if not grouped_findings:
            html_out.append("<div class='no-data'>No active threats found matching your keywords in the configured timeframe.</div>")
        else:
            for source_name, items in grouped_findings.items():
                html_out.append(f"<details class='source-section'>")
                html_out.append(f"<summary class='source-header'><h2>{escape_html(source_name)}</h2></summary>")
                html_out.append("<div class='threat-grid'>")

                for item in items:
                    safe_title = escape_html(item.title)
                    safe_date = escape_html(str(item.date_str))
                    safe_summary = escape_html(item.summary)
                    safe_link = escape_html(item.link)
                    safe_source = escape_html(source_name)
                    safe_technologies = escape_html(",".join(item.technologies_found))
                    safe_inclusions = escape_html(",".join(item.inclusions_found))

                    # Highlight occurrences in title and summary
                    display_title = safe_title
                    display_summary = safe_summary

                    # Simple text replacement for highlighting
                    for tech in item.technologies_found:
                        safe_tech = escape_html(tech)
                        display_title = re.sub(f"(?i)({re.escape(safe_tech)})", r'<span class="highlight-tech">\1</span>', display_title)
                        display_summary = re.sub(f"(?i)({re.escape(safe_tech)})", r'<span class="highlight-tech">\1</span>', display_summary)

                    for inc in item.inclusions_found:
                        safe_inc = escape_html(inc)
                        display_title = re.sub(f"(?i)({re.escape(safe_inc)})", r'<span class="highlight-inc">\1</span>', display_title)
                        display_summary = re.sub(f"(?i)({re.escape(safe_inc)})", r'<span class="highlight-inc">\1</span>', display_summary)

                    # Add span back safely so that details pane can render it
                    # Overwrite summary attribute so details pane gets the highlighted HTML
                    safe_summary_html = display_summary

                    # Store data in attributes, render condensed view
                    html_out.append(f"<div class='threat-card' style='cursor:pointer;' data-title='{safe_title}' data-date='{safe_date}' data-summary='{safe_summary_html}' data-link='{safe_link}' data-source='{safe_source}' data-technologies='{safe_technologies}' data-inclusions='{safe_inclusions}' onclick='showDetails(this)'>")
                    html_out.append(f"<h3 class='threat-title'>{display_title}</h3>")
                    html_out.append(f"<div class='threat-date'>{safe_date}</div>")

                    html_out.append("<div class='threat-keywords'>")
                    for tech in item.technologies_found:
                        html_out.append(f"<span class='technology-tag'>{escape_html(tech)}</span>")
                    for inc in item.inclusions_found:
                        html_out.append(f"<span class='inclusion-tag'>{escape_html(inc)}</span>")
                    html_out.append("</div>")

                    html_out.append("</div>") # Close threat-card

                html_out.append("</div>") # Close threat-grid
                html_out.append("</details>") # Close source-section

        # Add the dynamic detail view pane (hidden by default, moved via JS)
        html_out.append("<div id='dynamicDetail' style='display:none; grid-column: 1 / -1; width: 100%; padding:20px; border: 2px solid var(--accent-blue); background-color: var(--bg-card); border-radius: 8px; margin-top: 10px; margin-bottom: 20px;'>")
        html_out.append("<div style='display:flex; justify-content:space-between; align-items:center; border-bottom: 1px solid var(--border-color); padding-bottom: 10px; margin-bottom:15px;'>")
        html_out.append("<h2 style='margin:0; color:var(--text-main);'>Detailed View</h2>")
        html_out.append("<button onclick='document.getElementById(\"dynamicDetail\").style.display=\"none\";' style='background:none; border:1px solid var(--border-color); color:var(--text-muted); cursor:pointer; padding:5px 10px; border-radius:4px;'>Close</button>")
        html_out.append("</div>")
        html_out.append("<div id='detailContent'></div>")
        html_out.append("</div>")

        html_out.append("</div>")
        html_out.append(js_logic)
        # Build selection lists for the filter modal
        html_out.append("<!-- Filter Selection Modal -->")
        html_out.append("<div id='filterModal' style='display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.8); z-index:1000;'>")
        html_out.append("<div style='position:absolute; top:50%; left:50%; transform:translate(-50%, -50%); background:var(--bg-card); padding:30px; border-radius:8px; border:1px solid var(--border-color); min-width:400px; max-width:80%; max-height:80%; overflow-y:auto;'>")

        html_out.append("<div style='display:flex; justify-content:space-between; border-bottom:1px solid var(--border-color); padding-bottom:10px; margin-bottom:20px;'>")
        html_out.append("<h2 id='filterModalTitle' style='margin:0;'>Select Filter</h2>")
        html_out.append("<button onclick='document.getElementById(\"filterModal\").style.display=\"none\";' style='background:none; border:none; color:var(--text-muted); cursor:pointer; font-size:1.5em;'>&times;</button>")
        html_out.append("</div>")

        # Sources list
        html_out.append("<div id='modal-sources' style='display:none; display:flex; flex-direction:column; gap:10px;'>")
        for src in grouped_findings.keys():
            safe_src = escape_html(src)
            html_out.append(f"<button onclick='selectFilterOption(\"sources\", this)' data-val='{safe_src}' style='padding:10px; text-align:left; background:var(--bg-main); color:var(--accent-blue); border:1px solid var(--border-color); border-radius:4px; cursor:pointer;'>{safe_src}</button>")
        html_out.append("</div>")

        # Technologies list
        html_out.append("<div id='modal-technologies' style='display:none; display:flex; flex-direction:column; gap:10px;'>")
        for tech in self.technologies:
            safe_tech = escape_html(tech)
            html_out.append(f"<button onclick='selectFilterOption(\"technologies\", this)' data-val='{safe_tech}' style='padding:10px; text-align:left; background:var(--bg-main); color:var(--accent-blue); border:1px solid var(--border-color); border-radius:4px; cursor:pointer;'>{safe_tech}</button>")
        html_out.append("</div>")

        # Inclusions list
        html_out.append("<div id='modal-inclusions' style='display:none; display:flex; flex-direction:column; gap:10px;'>")
        for inc in self.inclusions:
            safe_inc = escape_html(inc)
            html_out.append(f"<button onclick='selectFilterOption(\"inclusions\", this)' data-val='{safe_inc}' style='padding:10px; text-align:left; background:var(--bg-main); color:var(--accent-green); border:1px solid var(--border-color); border-radius:4px; cursor:pointer;'>{safe_inc}</button>")
        html_out.append("</div>")

        html_out.append("</div></div>")

        html_out.append("</body></html>")

        with open(report_path, 'w', encoding='utf-8') as f:
            f.write("\n".join(html_out))

        print(report_path) # Print path so shell script knows where it is

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: analyzer.py <config_path> <data_dir> <output_dir> <css_path>", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    data_dir = sys.argv[2]
    output_dir = sys.argv[3]
    css_path = sys.argv[4]

    analyzer = IntelAnalyzer(config_path, data_dir, output_dir, css_path)
    analyzer.process_all()
    analyzer.generate_report()
