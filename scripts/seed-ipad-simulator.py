#!/usr/bin/env python3
"""Add one generated QA deck to an installed Slide Learning iPad simulator app.

Pass --reset to replace only the known Finance Review QA fixture. The reset is
refused when the existing directory is not the expected disposable fixture.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

arguments = list(sys.argv[1:])
reset = "--reset" in arguments
if "--pages" in arguments:
    pages_argument_index = arguments.index("--pages")
    if pages_argument_index + 1 >= len(arguments):
        raise SystemExit("Usage: seed-ipad-simulator.py [--reset] [--pages count] [simulator-UDID|booted]")
    try:
        page_count = int(arguments[pages_argument_index + 1])
    except ValueError:
        raise SystemExit("The --pages value must be an integer.")
    del arguments[pages_argument_index:pages_argument_index + 2]
else:
    page_count = 90
arguments = [argument for argument in arguments if argument != "--reset"]
if page_count < 1:
    raise SystemExit("The QA fixture must contain at least one page.")
if len(arguments) > 1:
    raise SystemExit("Usage: seed-ipad-simulator.py [--reset] [--pages count] [simulator-UDID|booted]")
simulator = arguments[0] if arguments else "booted"
container = subprocess.check_output([
    "xcrun", "simctl", "get_app_container", simulator,
    "com.kaikuppers.SlideLearning.ipad", "data",
], text=True).strip()
project_id = "3D3D88B0-579C-4F94-8AB2-30544CC31276"
directory = pathlib.Path(container) / "Library/Application Support/Slide Learning/Projects" / project_id
if directory.exists():
    if not reset:
        raise SystemExit("QA fixture already exists. Delete Finance Review in the simulator app before reseeding, or pass --reset.")
    metadata_path = directory / "project.json"
    try:
        metadata = json.loads(metadata_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Refusing to reset an unreadable project directory: {directory} ({error})")
    if metadata.get("id") != project_id or metadata.get("name") != "Finance Review":
        raise SystemExit(f"Refusing to reset a non-QA project directory: {directory}")
    shutil.rmtree(directory)
with tempfile.TemporaryDirectory(prefix="slide-learning-qa-") as temporary:
    source = pathlib.Path(temporary) / "source.pdf"
    subprocess.run([
        "swift", "-module-cache-path", str(pathlib.Path(temporary) / "swift-cache"),
        str(pathlib.Path(__file__).with_name("GenerateIPadTestPDF.swift")), str(source), str(page_count),
    ], check=True)
    directory.mkdir(parents=True)
    shutil.copy(source, directory / "source.pdf")
project = dict(
    schemaVersion=1, id=project_id, name="Finance Review", sourceFilename="Finance Review.pdf",
    pageCount=page_count, createdAt="2026-09-21T10:00:00Z", updatedAt="2026-09-21T10:00:00Z",
    lastOpenedAt="2026-09-21T10:00:00Z",
    slides=[dict(pageIndex=i, isSelected=i in [3, 5, 8], note="Lecture context" if i == 3 else "") for i in range(page_count)],
    viewPreferences=dict(focusedPageIndex=4, inspectorVisible=True, thumbnailSize="compact", filter="all"),
)
(directory / "project.json").write_text(json.dumps(project))
print(f"Seeded Finance Review ({page_count} pages). Relaunch the app to load it.")
