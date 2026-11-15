#include "my_application.h"
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#include "flutter/generated_plugin_registrant.h"
#include "../../../packages/fyr_core/linux/layer_overlay_helper.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  fyr_core::LayerOverlayState* overlay_state;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  delete self->overlay_state;
  self->overlay_state = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void first_frame_cb(MyApplication* self, FlView* view) {
  if (self->overlay_state && !self->overlay_state->config.start_hidden) {
    fyr_core::ShowLayerOverlay(self->overlay_state);
  }
}

// 1. Define activate
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "fyroverview");

  fyr_core::LayerOverlayConfig cfg;
  cfg.layer_namespace = "fyroverview";
  cfg.fullscreen = true;
  cfg.start_hidden = !fyr_core::ShouldStartShown(self->dart_entrypoint_arguments);
  cfg.hide_on_focus_out = false;
  fyr_core::ConfigureLayerOverlayWindow(window, cfg);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  GdkRGBA bg_color = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &bg_color);

  if (!self->overlay_state) {
    self->overlay_state = new fyr_core::LayerOverlayState();
  }
  fyr_core::AttachLayerOverlayChannel(self->overlay_state, window, view, cfg);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(window));
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  if (!cfg.start_hidden) {
    fyr_core::ShowLayerOverlay(self->overlay_state);
  }
}

// 2. Define local command line
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  
  // Clear any existing arguments before assigning new ones
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  if (fyr_core::ShouldStartShown(self->dart_entrypoint_arguments) &&
      fyr_core::ForwardToExistingOverlay("fyroverview", "show")) {
    *exit_status = 0;
    return TRUE;
  }

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
