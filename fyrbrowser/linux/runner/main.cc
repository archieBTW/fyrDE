#include <webview_cef/webview_cef_plugin.h>
#include "my_application.h"
#include <stdlib.h>

int main(int argc, char** argv) {
  setenv("GDK_CORE_DEVICE_EVENTS", "1", 1);
  
  // Create a new argv with stability flags
  // We disable engine smooth scrolling because we handle it in Flutter now.
  char** new_argv = (char**)malloc((argc + 2) * sizeof(char*));
  for (int i = 0; i < argc; ++i) {
    new_argv[i] = argv[i];
  }
  new_argv[argc] = (char*)"--disable-smooth-scrolling";
  new_argv[argc + 1] = NULL;
  int new_argc = argc + 1;

  int exit_code = initCEFProcesses(new_argc, new_argv);
  if (exit_code >= 0) {
    free(new_argv);
    return exit_code;
  }






  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
