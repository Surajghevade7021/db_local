import argparse

# ==============================
# INPUT ARGUMENTS
# ==============================

parser = argparse.ArgumentParser(description="CS Transfer Script")

parser.add_argument(
    "run_mode",
    choices=["DRY_RUN", "EXECUTE"],
    help="Run mode: DRY_RUN or EXECUTE"
)

parser.add_argument(
    "file_path",
    help="Full path of CSV file"
)

args = parser.parse_args()

RUN_MODE = args.run_mode
file_path = args.file_path
