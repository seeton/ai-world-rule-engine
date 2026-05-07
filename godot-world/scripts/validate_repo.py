#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_ROOT_DIR = Path(__file__).resolve().parent.parent
SCHEMA_RELATIVE_PATH = Path("rules/schema/rule_package.schema.json")
PACKAGE_RELATIVE_DIR = Path("rules/packages")
REFERENCE_GLOBS = ("project.godot", "scenes/**/*.tscn", "scripts/**/*.gd")
RES_REFERENCE_PATTERN = re.compile(r"res://[A-Za-z0-9_./-]+")
EXT_RESOURCE_USE_PATTERN = re.compile(r'ExtResource\("([^"]+)"\)')
EXT_RESOURCE_ATTRIBUTE_PATTERN = re.compile(r'([A-Za-z_]+)="([^"]*)"')


@dataclass
class ValidationProblem:
    file_path: Path
    message: str
    location: str = ""

    def format(self, root_dir: Path) -> str:
        try:
            display_path = self.file_path.relative_to(root_dir)
        except ValueError:
            display_path = self.file_path

        if self.location:
            return f"- {display_path}: {self.location}: {self.message}"
        return f"- {display_path}: {self.message}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Godot World rule packages and static repository references."
    )
    parser.add_argument(
        "--root",
        default=str(DEFAULT_ROOT_DIR),
        help="Path to the godot-world project root. Defaults to the checked-in project.",
    )
    return parser.parse_args()


def read_json_file(path: Path, problems: list[ValidationProblem]) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        problems.append(ValidationProblem(path, "File does not exist."))
    except json.JSONDecodeError as error:
        problems.append(
            ValidationProblem(
                path,
                f"Invalid JSON ({error.msg}).",
                f"line {error.lineno}, column {error.colno}",
            )
        )
    return None


def matches_type(value: Any, expected_type: str) -> bool:
    if expected_type == "object":
        return isinstance(value, dict)
    if expected_type == "array":
        return isinstance(value, list)
    if expected_type == "string":
        return isinstance(value, str)
    if expected_type == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected_type == "number":
        return (isinstance(value, int) or isinstance(value, float)) and not isinstance(value, bool)
    if expected_type == "boolean":
        return isinstance(value, bool)
    if expected_type == "null":
        return value is None
    return True


def describe_type(type_name: str) -> str:
    return "object" if type_name == "object" else type_name


def validate_against_schema(
    value: Any,
    schema: dict[str, Any],
    file_path: Path,
    location: str,
    problems: list[ValidationProblem],
) -> None:
    expected_types = schema.get("type")
    if expected_types is not None:
        if isinstance(expected_types, str):
            expected_type_names = [expected_types]
        else:
            expected_type_names = list(expected_types)

        if not any(matches_type(value, type_name) for type_name in expected_type_names):
            allowed_types = ", ".join(describe_type(type_name) for type_name in expected_type_names)
            problems.append(
                ValidationProblem(file_path, f"Expected type {allowed_types}.", location)
            )
            return

    if "const" in schema and value != schema["const"]:
        problems.append(
            ValidationProblem(
                file_path,
                f"Expected constant value {schema['const']!r}, got {value!r}.",
                location,
            )
        )

    enum_values = schema.get("enum")
    if enum_values is not None and value not in enum_values:
        problems.append(
            ValidationProblem(
                file_path,
                f"Expected one of {enum_values!r}, got {value!r}.",
                location,
            )
        )

    if isinstance(value, str):
        pattern = schema.get("pattern")
        if pattern is not None and re.search(pattern, value) is None:
            problems.append(
                ValidationProblem(
                    file_path,
                    f"Value {value!r} does not match /{pattern}/.",
                    location,
                )
            )

    if (isinstance(value, int) or isinstance(value, float)) and not isinstance(value, bool):
        minimum = schema.get("minimum")
        if minimum is not None and value < minimum:
            problems.append(
                ValidationProblem(
                    file_path,
                    f"Value {value!r} is smaller than minimum {minimum!r}.",
                    location,
                )
            )

    if isinstance(value, dict):
        required_keys = schema.get("required", [])
        for required_key in required_keys:
            if required_key not in value:
                problems.append(
                    ValidationProblem(
                        file_path,
                        f"Missing required property {required_key!r}.",
                        location,
                    )
                )

        property_schemas = schema.get("properties", {})
        additional_properties = schema.get("additionalProperties", True)
        for key, child_value in value.items():
            child_location = f"{location}.{key}"
            if key in property_schemas:
                validate_against_schema(
                    child_value, property_schemas[key], file_path, child_location, problems
                )
            elif additional_properties is False:
                problems.append(
                    ValidationProblem(
                        file_path,
                        f"Unexpected property {key!r}.",
                        child_location,
                    )
                )
            elif isinstance(additional_properties, dict):
                validate_against_schema(
                    child_value, additional_properties, file_path, child_location, problems
                )

    if isinstance(value, list) and "items" in schema:
        item_schema = schema["items"]
        for index, item in enumerate(value):
            validate_against_schema(item, item_schema, file_path, f"{location}[{index}]", problems)


def validate_rule_packages(root_dir: Path, problems: list[ValidationProblem]) -> int:
    schema_path = root_dir / SCHEMA_RELATIVE_PATH
    schema = read_json_file(schema_path, problems)
    if schema is None:
        return 0
    if not isinstance(schema, dict):
        problems.append(ValidationProblem(schema_path, "Schema must be a JSON object."))
        return 0

    package_dir = root_dir / PACKAGE_RELATIVE_DIR
    if not package_dir.is_dir():
        problems.append(ValidationProblem(package_dir, "Rule package directory does not exist."))
        return 0

    package_paths = sorted(package_dir.glob("*.rule.json"))
    if not package_paths:
        problems.append(ValidationProblem(package_dir, "No rule package files were found."))
        return 0

    package_ids: dict[str, Path] = {}
    for package_path in package_paths:
        package_data = read_json_file(package_path, problems)
        if package_data is None:
            continue

        validate_against_schema(package_data, schema, package_path, "$", problems)
        if not isinstance(package_data, dict):
            continue

        package_id = package_data.get("package_id")
        if isinstance(package_id, str):
            previous_path = package_ids.get(package_id)
            if previous_path is not None and previous_path != package_path:
                problems.append(
                    ValidationProblem(
                        package_path,
                        f"Duplicate package_id {package_id!r}; already defined in {previous_path.name}.",
                    )
                )
            else:
                package_ids[package_id] = package_path

    return len(package_paths)


def validate_scene_ext_resources(
    root_dir: Path, scene_path: Path, text: str, problems: list[ValidationProblem]
) -> None:
    ext_resources: dict[str, str] = {}
    for line_number, line in enumerate(text.splitlines(), start=1):
        stripped_line = line.strip()
        if not stripped_line.startswith("[ext_resource "):
            continue

        attributes = dict(EXT_RESOURCE_ATTRIBUTE_PATTERN.findall(stripped_line))
        resource_id = attributes.get("id", "")
        resource_path = attributes.get("path", "")

        if not resource_id:
            problems.append(
                ValidationProblem(scene_path, "Missing ext_resource id.", f"line {line_number}")
            )
            continue

        if resource_id in ext_resources:
            problems.append(
                ValidationProblem(
                    scene_path,
                    f"Duplicate ext_resource id {resource_id!r}.",
                    f"line {line_number}",
                )
            )
            continue

        if not resource_path:
            problems.append(
                ValidationProblem(
                    scene_path,
                    f"ext_resource {resource_id!r} is missing a path attribute.",
                    f"line {line_number}",
                )
            )
            continue

        ext_resources[resource_id] = resource_path

    for match in EXT_RESOURCE_USE_PATTERN.finditer(text):
        resource_id = match.group(1)
        if resource_id in ext_resources:
            continue

        line_number = text.count("\n", 0, match.start()) + 1
        problems.append(
            ValidationProblem(
                scene_path,
                f'ExtResource("{resource_id}") does not match any [ext_resource] id.',
                f"line {line_number}",
            )
        )


def resolve_repository_reference(root_dir: Path, reference: str) -> tuple[Path | None, str | None]:
    relative_path = Path(reference.removeprefix("res://"))
    if ".." in relative_path.parts:
        return None, f"{reference} is not a valid repository reference."

    target_path = (root_dir / relative_path).resolve(strict=False)
    try:
        target_path.relative_to(root_dir)
    except ValueError:
        return None, f"{reference} is not a valid repository reference."

    return target_path, None


def validate_reference_files(root_dir: Path, problems: list[ValidationProblem]) -> int:
    reference_files: set[Path] = set()
    for pattern in REFERENCE_GLOBS:
        for path in root_dir.glob(pattern):
            if path.is_file():
                reference_files.add(path)

    for path in sorted(reference_files):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            problems.append(ValidationProblem(path, "File is not valid UTF-8 text."))
            continue

        for reference in sorted(set(RES_REFERENCE_PATTERN.findall(text))):
            target_path, error_message = resolve_repository_reference(root_dir, reference)
            if error_message is not None:
                problems.append(ValidationProblem(path, error_message))
                continue

            if not target_path.exists():
                problems.append(
                    ValidationProblem(path, f"{reference} does not exist in the repository.")
                )

        if path.suffix == ".tscn":
            validate_scene_ext_resources(root_dir, path, text, problems)

    return len(reference_files)


def main() -> int:
    args = parse_args()
    root_dir = Path(args.root).expanduser().resolve()

    problems: list[ValidationProblem] = []
    package_count = validate_rule_packages(root_dir, problems)
    reference_file_count = validate_reference_files(root_dir, problems)

    if problems:
        print("Repository validation failed.", file=sys.stderr)
        for problem in sorted(problems, key=lambda item: (str(item.file_path), item.location, item.message)):
            print(problem.format(root_dir), file=sys.stderr)
        return 1

    print("Repository validation passed.")
    print(f"- rule packages: {package_count}")
    print(f"- reference files: {reference_file_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
