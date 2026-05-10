extends RefCounted
class_name WorldOpResult

# Builders for the uniform World Operation result Dictionary returned by
# every operation through the dispatcher. All surfaces (CLI parser, GUI,
# GM, Codex, automation) consume this same shape so they cannot drift in
# what they consider success / error / diff / rollback.
#
# Result schema:
# {
#   "operation_type": String,
#   "status":         "ok" | "validation_error" | "execution_error" | "dry_run",
#   "exit_code":      int,                       # CLI mapping: 0 / 2 / 3 / 0
#   "lines":          PackedStringArray,         # human-readable
#   "payload":        Dictionary,                # machine-readable, --json target
#   "diff":           Dictionary,                # before/after summary (may be empty)
#   "audit": {
#     "operation_id": String,
#     "timestamp":    String                     # ISO-ish
#   },
#   "rollback": {
#     "supported":    bool,
#     "hint":         String                     # human-readable hint or ""
#   },
#   "validation": {
#     "errors":       PackedStringArray,
#     "warnings":     PackedStringArray
#   }
# }

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_RUNTIME := 3


static func ok(operation_type: String, lines: PackedStringArray, payload: Dictionary, diff: Dictionary = {}, rollback: Dictionary = {}, warnings: PackedStringArray = PackedStringArray()) -> Dictionary:
	return {
		"operation_type": operation_type,
		"status": "ok",
		"exit_code": EXIT_OK,
		"lines": lines,
		"payload": payload,
		"diff": diff,
		"audit": {},
		"rollback": _normalize_rollback(rollback),
		"validation": {
			"errors": PackedStringArray(),
			"warnings": warnings
		}
	}


static func dry_run(operation_type: String, lines: PackedStringArray, payload: Dictionary, diff_preview: Dictionary = {}, rollback: Dictionary = {}, warnings: PackedStringArray = PackedStringArray()) -> Dictionary:
	return {
		"operation_type": operation_type,
		"status": "dry_run",
		"exit_code": EXIT_OK,
		"lines": lines,
		"payload": payload,
		"diff": diff_preview,
		"audit": {},
		"rollback": _normalize_rollback(rollback),
		"validation": {
			"errors": PackedStringArray(),
			"warnings": warnings
		}
	}


static func validation_error(operation_type: String, errors: PackedStringArray, warnings: PackedStringArray = PackedStringArray()) -> Dictionary:
	return {
		"operation_type": operation_type,
		"status": "validation_error",
		"exit_code": EXIT_USAGE,
		"lines": errors,
		"payload": {"message": " / ".join(errors)},
		"diff": {},
		"audit": {},
		"rollback": _normalize_rollback({}),
		"validation": {
			"errors": errors,
			"warnings": warnings
		}
	}


static func execution_error(operation_type: String, lines: PackedStringArray, payload: Dictionary, warnings: PackedStringArray = PackedStringArray()) -> Dictionary:
	return {
		"operation_type": operation_type,
		"status": "execution_error",
		"exit_code": EXIT_RUNTIME,
		"lines": lines,
		"payload": payload,
		"diff": {},
		"audit": {},
		"rollback": _normalize_rollback({}),
		"validation": {
			"errors": PackedStringArray(),
			"warnings": warnings
		}
	}


static func _normalize_rollback(rollback: Dictionary) -> Dictionary:
	return {
		"supported": bool(rollback.get("supported", false)),
		"hint": String(rollback.get("hint", ""))
	}
