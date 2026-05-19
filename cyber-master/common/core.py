import os
import yaml
import logging
from typing import Dict, Any, Optional, List
from pydantic import BaseModel, Field, ConfigDict
from rich.logging import RichHandler
from rich.console import Console

# 1. Unified JSON Schema model
class UnifiedSchema(BaseModel):
    """
    Unified JSON Schema for cyber-master toolset.
    """
    target: str = Field(..., description="Target identifier (e.g., IP, domain, URL, email)")
    risk_score: int = Field(default=0, description="Risk score associated with the target")
    risk_reasons: Optional[List[str]] = Field(default_factory=list, description="Reasons for the calculated risk score")

    # Optional nested dictionaries for specific modules
    asn: Optional[Dict[str, Any]] = Field(default=None, description="ASN enrichment data")
    tls: Optional[Dict[str, Any]] = Field(default=None, description="TLS certificate enrichment data")
    mail: Optional[Dict[str, Any]] = Field(default=None, description="Mail header analysis data")
    ioc: Optional[Dict[str, Any]] = Field(default=None, description="Indicators of Compromise data")

    # Allow arbitrary extra fields for flexibility
    model_config = ConfigDict(extra="allow")

# 2. Configuration Loader
def load_config(config_path: str = "cyber-master/config/keys.yaml") -> Dict[str, Any]:
    """
    Loads configuration (API keys, etc.) from a YAML file.
    Falls back to environment variables if the file is missing or a key is not present.
    """
    config = {}
    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                yaml_config = yaml.safe_load(f)
                if isinstance(yaml_config, dict):
                    config = yaml_config
        except Exception as e:
            get_logger(__name__).warning(f"Failed to load config from {config_path}: {e}")
    else:
        get_logger(__name__).info(f"Config file {config_path} not found. Relying on environment variables.")

    # Example: Overwrite with environment variables if they exist
    # VT_API_KEY could be in config["VT_API_KEY"] or os.environ["VT_API_KEY"]
    for key in os.environ:
        if key.endswith("_API_KEY") or key.endswith("_TOKEN"):
            config[key] = os.environ[key]

    return config

# 3. Base Logger Setup
def get_logger(name: str, level: int = logging.INFO) -> logging.Logger:
    """
    Returns a configured logger using rich for pretty terminal output.
    """
    logger = logging.getLogger(name)

    # Prevent adding handlers multiple times if get_logger is called repeatedly
    if not logger.handlers:
        logger.setLevel(level)

        # Create rich handler
        console = Console(stderr=True)
        rich_handler = RichHandler(console=console, rich_tracebacks=True, markup=True)
        rich_handler.setLevel(level)

        # Create formatter
        formatter = logging.Formatter("%(message)s")
        rich_handler.setFormatter(formatter)

        logger.addHandler(rich_handler)

    return logger

# Example usage/test if run directly
if __name__ == "__main__":
    logger = get_logger("core_test")
    logger.info("Core module initialized successfully.")

    # Test Pydantic model
    try:
        data = UnifiedSchema(
            target="example.com",
            risk_score=50,
            tls={"issuer": "Let's Encrypt"},
            extra_field="This is allowed"
        )
        logger.info(f"Created UnifiedSchema instance: {data.model_dump_json(indent=2)}")
    except Exception as e:
        logger.error(f"Failed to create UnifiedSchema: {e}")
