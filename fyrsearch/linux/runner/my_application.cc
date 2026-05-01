#include "my_application.h"
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

// Intercept close requests (e.g., Sway kill command)
static gboolean on_window_delete_event(GtkWidget* widget, GdkEvent* event, gpointer user_data) {
  system("swaymsg move scratchpad > /dev/null 2>&1");
  return TRUE; // Prevent the window from actually closing
}

// 1. Define activate
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // --- ENABLE TRANSPARENCY & REMOVE DECORATIONS ---
// --- ENABLE TRANSPARENCY & REMOVE DECORATIONS ---
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen *screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual *visual = gdk_screen_get_rgba_visual(screen);
  if (visual != NULL) {
      gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }
  gtk_window_set_decorated(window, FALSE);

  // --- FORCE GTK WINDOW TRANSPARENCY VIA CSS ---
  GtkCssProvider* css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css, "window, decoration { background: transparent; }", -1, nullptr);
  gtk_style_context_add_provider_for_screen(screen, GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  // ------------------------------------------------
  // ------------------------------------------------

  gboolean use_header_bar = TRUE;
#ifdef G_OS_UNIX
  gboolean is_wayland = FALSE;
  GdkDisplay* display = gdk_display_get_default();
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    is_wayland = TRUE;
  }
  if (is_wayland) {
    use_header_bar = FALSE;
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "sway_launcher");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "sway_launcher");
  }

  gtk_window_set_default_size(window, 1280, 720);
  
  // Intercept the window close event so Super+Q hides it instead of killing it
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete_event), nullptr);

  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // --- MAKE FLUTTER VIEW BACKGROUND TRANSPARENT ---
  GdkRGBA bg_color = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &bg_color);
  // ------------------------------------------------

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// 2. Define local command line
// 2. Define local command line
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  
  // Clear any existing arguments before assigning new ones
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

// 3. Define startup
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// 4. Wire them all up in class_init!
static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}