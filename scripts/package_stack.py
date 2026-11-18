"""Build a Resource Manager ZIP from a fixed list; no credentials or state."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.1.0"
FILES = [
    "main.tf", "variables.tf", "versions.tf", "security.tf", "outputs.tf",
    ".terraform.lock.hcl", "schema.yaml", "README.md",
    "terraform.tfvars.example", "tests/network.tftest.hcl",
]


def main():
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
