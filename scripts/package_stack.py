"""Build a Resource Manager ZIP from a fixed list; no credentials or state."""
from pathlib import Path
import hashlib
import zipfile
import re

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.1.1"
FILES = [
    "main.tf", "variables.tf", "versions.tf", "security.tf", "outputs.tf",
    ".terraform.lock.hcl", "schema.yaml", "README.md",
    "terraform.tfvars.example", "tests/network.tftest.hcl",
]


def main():
    # Regression guard: Resource Manager must provide the stack region.
    variables = (ROOT / "variables.tf").read_text(encoding="utf-8-sig")
    region_block = re.search(r'(?ms)^variable "region" \{.*?^\}', variables)
    assert region_block and not re.search(r"^\s*default\s*=", region_block[0], re.M), "region must have no Terraform default"
    schema = (ROOT / "schema.yaml").read_text(encoding="utf-8-sig")
    region_field = re.search(r"(?ms)^  region:\n.*?(?=^  [a-zA-Z0-9_]+:|\Z)", schema)
    assert region_field and not re.search(r"^    default:", region_field[0], re.M), "region must have no schema default"
    assert "region = var.region" in (ROOT / "versions.tf").read_text(encoding="utf-8-sig"), "provider must use the supplied region"
    output_dir = ROOT / "dist"
    output_dir.mkdir(exist_ok=True)
    archive = output_dir / f"oke-network-resource-manager-v{VERSION}.zip"
    for name in FILES:
        if not (ROOT / name).is_file():
            raise FileNotFoundError(f"Missing required file: {name}")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        for name in FILES:
            bundle.write(ROOT / name, name)
    with zipfile.ZipFile(archive) as bundle:
        assert set(bundle.namelist()) == set(FILES)
        assert bundle.testzip() is None
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(archive.suffix + ".sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="ascii"
    )
    print(f"Created {archive.name} ({archive.stat().st_size:,} bytes)")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
