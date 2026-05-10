extends SceneTree

# Smoke test for the C-key inspect overlay's parity with the headless CLI.
# Verifies that the shared InspectReport.build() reports the same key fields
# the CLI prints, against the same WorldState — so the overlay is a faithful
# preview of `bash scripts/world_cli.sh ... -- inspect`.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const InspectReportScript = preload("res://scripts/cli/inspect_report.gd")

const KEY_FIELDS := [
	"installed_rule_count",
	"installed_package_count",
	"disabled_rule_ids",
	"rules_with_unmet_requirements"
]


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var worlds_to_release: Array = []

	var world := WorldStateScript.new()
	worlds_to_release.append(world)

	var install_result: Dictionary = world.create_rule_from_patch({
		"template_id": "hunger",
		"id": "overlay_smoke_rule",
		"metadata": {"package_id": "overlay.smoke"}
	})
	if String(install_result.get("status", "")) != "installed":
		exit_code = 1
		failure_message = "Failed to install smoke rule: %s" % JSON.stringify(install_result)
	else:
		var report_before: Dictionary = InspectReportScript.build(world, "")
		if int(report_before.get("installed_rule_count", -1)) != 1:
			exit_code = 1
			failure_message = "Expected installed_rule_count=1, got %s" % str(report_before.get("installed_rule_count"))
		elif (report_before.get("disabled_rule_ids", []) as Array).size() != 0:
			exit_code = 1
			failure_message = "Expected no disabled rules initially, got %s" % JSON.stringify(report_before.get("disabled_rule_ids"))
		else:
			# Disable the rule and verify the report reflects it the same way the CLI would.
			var disable_result: Dictionary = world.set_rule_enabled("overlay_smoke_rule", false)
			if String(disable_result.get("status", "")) != "disabled":
				exit_code = 1
				failure_message = "Failed to disable rule: %s" % JSON.stringify(disable_result)
			else:
				var report_after: Dictionary = InspectReportScript.build(world, "")
				var disabled_ids: Array = report_after.get("disabled_rule_ids", [])
				if disabled_ids.size() != 1 or String(disabled_ids[0]) != "overlay_smoke_rule":
					exit_code = 1
					failure_message = "disabled_rule_ids mismatch after disable: %s" % JSON.stringify(disabled_ids)
				else:
					var status: Dictionary = report_after.get("world_status", {})
					var collapse_signals: Array = status.get("collapse_signals", [])
					if not collapse_signals.has("disabled_rules_present"):
						exit_code = 1
						failure_message = "collapse_signals missing 'disabled_rules_present': %s" % JSON.stringify(collapse_signals)
					else:
						# Two consecutive build() calls on the same world must be deterministic.
						var first := InspectReportScript.build(world, "")
						var second := InspectReportScript.build(world, "")
						for field in KEY_FIELDS:
							if JSON.stringify(first.get(field)) != JSON.stringify(second.get(field)):
								exit_code = 1
								failure_message = "Non-deterministic field '%s'" % field
								break

	for w in worlds_to_release:
		if is_instance_valid(w):
			w.free()

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)
