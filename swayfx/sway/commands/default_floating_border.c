#include "log.h"
#include "sway/commands.h"
#include "sway/config.h"
#include "sway/tree/container.h"

struct cmd_results *cmd_default_floating_border(int argc, char **argv) {
	struct cmd_results *error = NULL;
	if ((error = checkarg(argc, "default_floating_border",
					EXPECTED_AT_LEAST, 1))) {
		return error;
	}

	if (strcmp(argv[0], "none") == 0) {
		config->floating_border = B_NONE;
		config->floating_border_auto = false;
	} else if (strcmp(argv[0], "normal") == 0) {
		config->floating_border = B_NORMAL;
		config->floating_border_auto = false;
	} else if (strcmp(argv[0], "pixel") == 0) {
		config->floating_border = B_PIXEL;
		config->floating_border_auto = false;
	} else if (strcmp(argv[0], "auto") == 0) {
		config->floating_border = B_PIXEL;
		config->floating_border_auto = true;
	} else {
		return cmd_results_new(CMD_INVALID,
				"Expected 'default_floating_border <none|normal|pixel|auto>' "
				"or 'default_floating_border <normal|pixel|auto> <px>'");
	}
	if (argc == 2) {
		config->floating_border_thickness = atoi(argv[1]);
	}

	return cmd_results_new(CMD_SUCCESS, NULL);
}
