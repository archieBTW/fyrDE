#include <webview_cef/webview_cef_plugin.h>
#include "my_application.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int main(int argc, char** argv) {
  setenv("GDK_CORE_DEVICE_EVENTS", "1", 1);
  
  // Check if this is a CEF helper process (renderer, gpu, etc.)
  // CEF spawns these with specific command line flags.
  bool is_cef_helper = false;
  for (int i = 0; i < argc; ++i) {
    if (strncmp(argv[i], "--type=", 7) == 0) {
      is_cef_helper = true;
      break;
    }
  }

  // If it's a helper, initialize CEF immediately and let it take over.
  if (is_cef_helper) {
    return initCEFProcesses(argc, argv);
  }

  // Not a helper, so it's a user-initiated launch (Primary or Remote).
  g_autoptr(MyApplication) app = my_application_new();
  
  // Register with GApplication to detect if we are a remote instance.
  g_autoptr(GError) error = nullptr;
  if (!g_application_register(G_APPLICATION(app), nullptr, &error)) {
    fprintf(stderr, "Failed to register GApplication: %s\n", error->message);
    return 1;
  }

  // If this is a remote instance, it means FyrBrowser is already running.
  // We send the command line arguments to the primary instance and exit.
  if (g_application_get_is_remote(G_APPLICATION(app))) {
    return g_application_run(G_APPLICATION(app), argc, argv);
  }

  // This is the PRIMARY instance.
  // We add stability flags and initialize CEF before starting the Flutter loop.
  char** new_argv = (char**)malloc((argc + 2) * sizeof(char*));
  for (int i = 0; i < argc; ++i) {
    new_argv[i] = argv[i];
  }
  new_argv[argc] = (char*)"--disable-smooth-scrolling";
  new_argv[argc + 1] = NULL;
  int new_argc = argc + 1;

  int exit_code = initCEFProcesses(new_argc, new_argv);
  if (exit_code >= 0) {
    // This branch should ideally not be reached for the primary process.
    free(new_argv);
    return exit_code;
  }

  // Run the GApplication loop (Flutter will be initialized in 'activate').
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  
  free(new_argv);
  return status;
}
