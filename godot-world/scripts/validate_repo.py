#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional


ROOT_DIR = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT_DIR / "rules/schema/rule_package.schema.json"
PACKAGE_DIR = ROOT_DIR / "rules/packages"
REFERENCE_GLOBS = ("project.godot", "scenes/**/*.tscn", "scripts/**/*.gd")
RESOURCE_PATTERN = re.compile(r"res://[A-Za-z0-9_./-]+")
EXT_RESOURCE_DEF_PATTERN = re.compile(r'^\[ext_resource\b[^\]]*\bid="([^"]+)"', re.MULTILINE)
EXT_RESOURCE_USE_PATTERN = re.compile(r'ExtResource\("([^"]+)"\)')


@dataclass
class ValidationError:
    source: str
    message: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Godot World rule packages and static Godot resource references."
    )
    parser.add_argument(
        "--root",
        default=str(ROOT_DIR),
        help="Path to the godot-world project root. Defaults to the repository copy next to this script.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root_dir = Path(args.root).resolve()
    schema_path = root_dir / "rules/schema/rule_package.schema.json"
    package_dir = root_dir / "rules/packages"

    errors: list[ValidationError] = []
    errors.extend(validate_rule_packages(root_dir, schema_path, package_dir))
    errors.extend(validate_static_references(root_dir))

    if errors:
        print(f"Validation failed with {len(errors)} error(s):")
        for error in errors:
            print(f"- {error.source}: {error.message}")
        return 1

    package_count = len(sorted(package_dir.glob("*.rule.json")))
    reference_file_count = count_reference_files(root_dir)
    print(
        "Validation passed:"
        f" {package_count} rule package(s) matched the schema and"
        f" {reference_file_count} Godot file(s) had valid static resource references."
    )
    return 0


def validate_rule_packages(root_dir: Path, schema_path: Path, package_dir: Path) -> list[ValidationError]:
    errors: list[ValidationError] = []
    schema = load_json(schema_path, errors, str(schema_path.relative_to(root_dir)))
    if schema is None:
        return errors

    package_files = sorted(package_dir.glob("*.rule.json"))
    if not package_files:
        errors.append(ValidationError(str(package_dir.relative_to(root_dir)), "No rule package files were found."))
        return errors

    package_ids: dict[str, Path] = {}
    for package_path in package_files:
        rel_path = str(package_path.relative_to(root_dir))
        package_data = load_json(package_path, errors, rel_path)
        if package_data is None:
            continue

        if not isinstance(package_data, dict):
            errors.append(ValidationError(rel_path, "Expected the package file root value to be an object."))
            continue

        errors.extend(validate_schema(package_data, schema, rel_path))

        package_id = package_data.get("package_id")
        if isinstance(package_id, str) and package_id:
            previous_path = package_ids.get(package_id)
            if previous_path is not None:
                errors.append(
                    ValidationError(
                        rel_path,
                        f"package_id '{package_id}' is duplicated in {previous_path.relative_to(root_dir)}.",
                    )
                )
            else:
                package_ids[package_id] = package_path

            expected_file_name = f"{package_id.rsplit('.', 1)[-1]}.rule.json"
            if package_path.name != expected_file_name:
                errors.append(
                    ValidationError(
                        rel_path,
                        f"File name should be '{expected_file_name}' to match package_id '{package_id}'.",
                    )
                )

        suggested_pr_target = package_data.get("suggested_pr_target")
        if isinstance(suggested_pr_target, dict):
            target_package_id = suggested_pr_target.get("package_id")
            if isinstance(package_id, str) and target_package_id != package_id:
                errors.append(
                    ValidationError(
                        rel_path,
                        "suggested_pr_target.package_id must match package_id for repository packages.",
                    )
                )

    return errors


def validate_static_references(root_dir: Path) -> list[ValidationError]:
    errors: list[ValidationError] = []
    for path in iter_reference_files(root_dir):
        rel_path = str(path.relative_to(root_dir))
        text = path.read_text(encoding="utf-8")

        for resource_path in sorted(set(RESOURCE_PATTERN.findall(text))):
            target_path = root_dir / resource_path.removeprefix("res://")
            if not target_path.exists():
                errors.append(
                    ValidationError(rel_path, f"Missing referenced resource '{resource_path}'.")
                )

        if path.suffix == ".tscn":
            ext_resource_ids = set(EXT_RESOURCE_DEF_PATTERN.findall(text))
            for ext_resource_id in EXT_RESOURCE_USE_PATTERN.findall(text):
                if ext_resource_id not in ext_resource_ids:
                    errors.append(
                        ValidationError(
                            rel_path,
                            f"Scene references undefined ExtResource id '{ext_resource_id}'.",
                        )
                    )

    return errors


def iter_reference_files(root_dir: Path) -> list[Path]:
    files: list[Path] = []
    for pattern in REFERENCE_GLOBS:
        files.extend(root_dir.glob(pattern))
    return sorted({path for path in files if path.is_file()})


def count_reference_files(root_dir: Path) -> int:
    return len(iter_reference_files(root_dir))


def load_json(path: Path, errors: list[ValidationError], source: str) -> Optional[Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        errors.append(ValidationError(source, "File does not exist."))
    except json.JSONDecodeError as exc:
        errors.append(ValidationError(source, f"Invalid JSON: {exc.msg} (line {exc.lineno}, column {exc.colno})."))
    return None


def validate_schema(value: Any, schema: dict[str, Any], source: str, pointer: str = "$") -> list[ValidationError]:
    errors: list[ValidationError] = []

    if "type" in schema and not matches_type(value, schema["type"]):
        errors.append(
            ValidationError(source, f"{pointer}: expected {describe_types(schema['type'])}, got {describe_value(value)}.")
        )
        return errors

    if "const" in schema and value != schema["const"]:
        errors.append(ValidationError(source, f"{pointer}: expected constant value {schema['const']!r}."))

    if "enum" in schema and value not in schema["enum"]:
        allowed = ", ".join(repr(option) for option in schema["enum"])
        errors.append(ValidationError(source, f"{pointer}: expected one of {allowed}."))

    if "pattern" in schema and isinstance(value, str) and re.search(schema["pattern"], value) is None:
        errors.append(ValidationError(source, f"{pointer}: value {value!r} does not match pattern {schema['pattern']!r}."))

    if "minimum" in schema and is_number(value) and value < schema["minimum"]:
        errors.append(ValidationError(source, f"{pointer}: value {value} is smaller than minimum {schema['minimum']}."))

    if isinstance(value, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in value:
                errors.append(ValidationError(source, f"{pointer}: missing required property '{key}'."))

        properties = schema.get("properties", {})
        for key, property_value in value.items():
            if key in properties:
                errors.extend(validate_schema(property_value, properties[key], source, f"{pointer}.{key}"))
            elif schema.get("additionalProperties", True) is False:
                errors.append(ValidationError(source, f"{pointer}: unexpected property '{key}'."))

    if isinstance(value, list) and "items" in schema:
        item_schema = schema["items"]
        for index, item in enumerate(value):
            errors.extend(validate_schema(item, item_schema, source, f"{pointer}[{index}]"))

    return errors


def matches_type(value: Any, schema_type: Any) -> bool:
    expected_types = schema_type if isinstance(schema_type, list) else [schema_type]
    return any(matches_single_type(value, expected_type) for expected_type in expected_types)


def matches_single_type(value: Any, schema_type: str) -> bool:
    if schema_type == "object":
        return isinstance(value, dict)
    if schema_type == "array":
        return isinstance(value, list)
    if schema_type == "string":
        return isinstance(value, str)
    if schema_type == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if schema_type == "number":
        return is_number(value)
    if schema_type == "boolean":
        return isinstance(value, bool)
    if schema_type == "null":
        return value is None
    return False


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def describe_types(schema_type: Any) -> str:
    expected_types = schema_type if isinstance(schema_type, list) else [schema_type]
    return " or ".join(expected_types)


def describe_value(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


if __name__ == "__main__":
    sys.exit(main())
