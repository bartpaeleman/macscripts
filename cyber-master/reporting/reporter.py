import sys
import os
import json
import typer
from jinja2 import Environment, FileSystemLoader

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from common.core import UnifiedSchema, get_logger

app = typer.Typer()
logger = get_logger("reporter")

@app.command()
def generate(
    format: str = typer.Option("md", help="Format of the report: md, html, or pdf"),
    out: str = typer.Option(None, "--out", "-o", help="Custom output file path")
):
    """
    Reporting module.
    Reads UnifiedSchema JSON from stdin and generates a report on disk.
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

    templates_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'templates'))
    env = Environment(loader=FileSystemLoader(templates_dir))

    # If the user asks for PDF, we need to generate HTML first, so we map the format to the correct template
    template_file = "report.md.j2" if format == "md" else "report.html.j2"

    # We need to preserve the user's intended output format so we don't accidentally fall back
    intended_format = format

    try:
        template = env.get_template(template_file)
    except Exception as e:
        # Fallback to MD if HTML not found for simplicity
        if intended_format in ["html", "pdf"]:
             logger.warning("HTML template not found. Falling back to Markdown.")
             template = env.get_template("report.md.j2")
             intended_format = "md"
        else:
             logger.error(f"Failed to load template {template_file}: {e}")
             sys.exit(1)

    try:
        output = template.render(schema=schema)

        if out:
            output_file = os.path.abspath(out)
        else:
            # Create a safe filename
            safe_target = schema.target.replace("/", "_").replace("\\", "_")
            output_file = f"report_{safe_target}.{intended_format}"

        if intended_format == "pdf":
            try:
                from weasyprint import HTML
                HTML(string=output).write_pdf(output_file)
                logger.info(f"PDF Report generated successfully: {os.path.abspath(output_file)}")
            except ImportError:
                logger.error("weasyprint is not installed. Please install it to generate PDF reports.")
                sys.exit(1)
        else:
            with open(output_file, "w") as f:
                f.write(output)
            logger.info(f"Report generated successfully: {os.path.abspath(output_file)}")

    except Exception as e:
        logger.error(f"Failed to generate report: {e}")
        sys.exit(1)

if __name__ == "__main__":
    app()
