"""Download the Olist dataset from Kaggle into data/raw/.
Public Kaggle datasets download without an account, so a fresh clone
can run the whole pipeline after this one command."""

import argparse
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

DATASET_URL = "https://www.kaggle.com/api/v1/datasets/download/olistbr/brazilian-ecommerce"
PROJECT_ROOT = Path(__file__).resolve().parents[1]

EXPECTED_FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]


def download_zip(target: Path) -> None:
    request = urllib.request.Request(DATASET_URL, headers={"User-Agent": "olist-analytics/1.0"})
    with urllib.request.urlopen(request) as response, open(target, "wb") as out:
        total = 0
        while chunk := response.read(1 << 20):
            out.write(chunk)
            total += len(chunk)
    print(f"downloaded {total / 1e6:.1f} MB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, default=PROJECT_ROOT / "data" / "raw",
                        help="target folder (default: data/raw)")
    parser.add_argument("--force", action="store_true",
                        help="re-download even if all files exist")
    args = parser.parse_args()

    args.dest.mkdir(parents=True, exist_ok=True)
    missing = [name for name in EXPECTED_FILES if not (args.dest / name).exists()]
    if not missing and not args.force:
        print(f"all 9 files already in {args.dest}, nothing to do (use --force to re-download)")
        return

    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp) / "olist.zip"
        print(f"downloading {DATASET_URL}")
        download_zip(zip_path)
        with zipfile.ZipFile(zip_path) as archive:
            names = set(archive.namelist())
            absent = [name for name in EXPECTED_FILES if name not in names]
            if absent:
                sys.exit(f"archive is missing expected files: {absent}")
            for name in EXPECTED_FILES:
                archive.extract(name, args.dest)

    for name in EXPECTED_FILES:
        size_mb = (args.dest / name).stat().st_size / 1e6
        print(f"{name:<45} {size_mb:>6.1f} MB")
    print(f"9 files ready in {args.dest}")


if __name__ == "__main__":
    main()
