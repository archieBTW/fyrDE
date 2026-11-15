#include <string.h>
#include "sway/commands.h"
#include "sway/criteria.h"
#include "list.h"
#include "log.h"
#include "stringop.h"

static struct cmd_results *parse_for_window_criteria(const char *cmd_name,
		int argc, char **argv, struct criteria **out) {
	struct cmd_results *error = NULL;
	if ((error = checkarg(argc, cmd_name, EXPECTED_AT_LEAST, 2))) {
		return error;
	}

	char *err_str = NULL;
	struct criteria *criteria = criteria_parse(argv[0], &err_str);
	if (!criteria) {
		error = cmd_results_new(CMD_INVALID, "%s", err_str);
		free(err_str);
		return error;
	}

	criteria->type = CT_COMMAND;
	criteria->cmdlist = join_args(argv + 1, argc - 1);
	*out = criteria;
	return NULL;
}

struct cmd_results *cmd_for_window(int argc, char **argv) {
	struct criteria *criteria = NULL;
	struct cmd_results *error =
		parse_for_window_criteria("for_window", argc, argv, &criteria);
	if (error) {
		return error;
	}

	// Check if it already exists
	if (criteria_already_exists(criteria)) {
		sway_log(SWAY_DEBUG, "for_window already exists: '%s' -> '%s'",
				criteria->raw, criteria->cmdlist);
		criteria_destroy(criteria);
		return cmd_results_new(CMD_SUCCESS, NULL);
	}

	list_add(config->criteria, criteria);
	sway_log(SWAY_DEBUG, "for_window: '%s' -> '%s' added", criteria->raw, criteria->cmdlist);

	return cmd_results_new(CMD_SUCCESS, NULL);
}

struct cmd_results *cmd_unfor_window(int argc, char **argv) {
	struct criteria *criteria = NULL;
	struct cmd_results *error =
		parse_for_window_criteria("unfor_window", argc, argv, &criteria);
	if (error) {
		return error;
	}

	for (int i = config->criteria->length - 1; i >= 0; --i) {
		struct criteria *existing = config->criteria->items[i];
		if (criteria_is_equal(criteria, existing)) {
			sway_log(SWAY_DEBUG, "unfor_window: '%s' -> '%s' removed",
					existing->raw, existing->cmdlist);
			list_del(config->criteria, i);
			criteria_destroy(existing);
		}
	}

	criteria_destroy(criteria);
	return cmd_results_new(CMD_SUCCESS, NULL);
}
