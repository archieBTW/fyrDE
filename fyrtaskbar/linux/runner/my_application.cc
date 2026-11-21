#include "my_application.h"

#include <cstdlib>
#include <cstring>
#include <flutter_linux/flutter_linux.h>
#include <gtk-layer-shell.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "osd_overlay.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;
  OsdOverlay *osd_overlay;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication *self, FlView *view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static GdkMonitor *find_target_monitor(FlValue *args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  GdkDisplay *display = gdk_display_get_default();
  if (!display) return nullptr;

  int n = gdk_display_get_n_monitors(display);
  if (n <= 0) return nullptr;

  FlValue *x_val = fl_value_lookup_string(args, "x");
  FlValue *y_val = fl_value_lookup_string(args, "y");
  FlValue *w_val = fl_value_lookup_string(args, "width");
  FlValue *h_val = fl_value_lookup_string(args, "height");
  FlValue *model_val = fl_value_lookup_string(args, "model");

  const bool has_rect =
      x_val && y_val && w_val && h_val &&
      fl_value_get_type(x_val) == FL_VALUE_TYPE_INT &&
      fl_value_get_type(y_val) == FL_VALUE_TYPE_INT &&
      fl_value_get_type(w_val) == FL_VALUE_TYPE_INT &&
      fl_value_get_type(h_val) == FL_VALUE_TYPE_INT;
  const int req_x = has_rect ? static_cast<int>(fl_value_get_int(x_val)) : 0;
  const int req_y = has_rect ? static_cast<int>(fl_value_get_int(y_val)) : 0;
  const int req_w = has_rect ? static_cast<int>(fl_value_get_int(w_val)) : 0;
  const int req_h = has_rect ? static_cast<int>(fl_value_get_int(h_val)) : 0;

  const char *req_model =
      (model_val && fl_value_get_type(model_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(model_val)
          : nullptr;

  if (has_rect) {
    GdkMonitor *rect_match = nullptr;
    for (int i = 0; i < n; ++i) {
      GdkMonitor *mon = gdk_display_get_monitor(display, i);
      if (!mon) continue;
      GdkRectangle geom{};
      gdk_monitor_get_geometry(mon, &geom);
      if (std::abs(geom.x - req_x) <= 2 && std::abs(geom.y - req_y) <= 2 &&
          std::abs(geom.width - req_w) <= 2 &&
          std::abs(geom.height - req_h) <= 2) {
        if (req_model && req_model[0] != '\0') {
          const char *mon_model = gdk_monitor_get_model(mon);
          if (mon_model && std::strstr(mon_model, req_model) != nullptr) {
            return mon;
          }
        }
        if (!rect_match) rect_match = mon;
      }
    }
    if (rect_match) return rect_match;
  }

  if (req_model && req_model[0] != '\0') {
    for (int i = 0; i < n; ++i) {
      GdkMonitor *mon = gdk_display_get_monitor(display, i);
      if (!mon) continue;
      const char *mon_model = gdk_monitor_get_model(mon);
      if (mon_model && std::strstr(mon_model, req_model) != nullptr) {
        return mon;
      }
    }
  }
  return nullptr;
}

static void fyr_method_call_cb(FlMethodChannel *channel,
                               FlMethodCall *method_call, gpointer user_data) {
  GtkWindow *window = GTK_WINDOW(user_data);
  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "setSize") == 0) {
    FlValue *args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue *width_val = fl_value_lookup_string(args, "width");
      FlValue *height_val = fl_value_lookup_string(args, "height");
      if (width_val && height_val) {
        int width = fl_value_get_int(width_val);
        int height = fl_value_get_int(height_val);
        gtk_widget_set_size_request(GTK_WIDGET(window), width, height);
        gtk_window_resize(window, width, height);
      }
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (strcmp(method, "setMonitor") == 0) {
    gboolean bound = FALSE;
    if (gtk_layer_is_supported()) {
      GdkMonitor *target =
          find_target_monitor(fl_method_call_get_args(method_call));
      if (target != nullptr) {
        if (!gtk_layer_is_layer_window(window)) {
          gtk_layer_init_for_window(window);
        }
        if (gtk_layer_get_monitor(window) != target) {
          gboolean was_mapped = gtk_widget_get_mapped(GTK_WIDGET(window));
          if (was_mapped) {
            gtk_widget_hide(GTK_WIDGET(window));
          }
          gtk_layer_set_monitor(window, target);
          if (was_mapped) {
            gtk_widget_show(GTK_WIDGET(window));
          }
        }
        bound = TRUE;
      }
    }
    g_autoptr(FlValue) result = fl_value_new_bool(bound);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (strcmp(method, "isLayerSupported") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(gtk_layer_is_supported() ? TRUE : FALSE);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (strcmp(method, "setNamespace") == 0) {
    FlValue *args = fl_method_call_get_args(method_call);
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_STRING &&
        gtk_layer_is_layer_window(window)) {
      gtk_layer_set_namespace(window, fl_value_get_string(args));
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application) {
  MyApplication *self = MY_APPLICATION(application);
  GtkWindow *window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = FALSE;
#ifdef GDK_WINDOWING_X11
  GdkScreen *screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    use_header_bar = FALSE;
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar *header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "fyrtaskbar");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "fyrtaskbar");
  }

  bool is_desktop = false;
  if (self->dart_entrypoint_arguments) {
    for (int i = 0; self->dart_entrypoint_arguments[i] != nullptr; ++i) {
      if (strcmp(self->dart_entrypoint_arguments[i], "--desktop") == 0) {
        is_desktop = true;
        break;
      }
    }
  }

  // Initialize gtk-layer-shell BEFORE gtk_widget_realize so wlroots >= 0.20
  // never receives an unanchored 0x0 initial layer surface configure request.
  if (gtk_layer_is_supported()) {
    gtk_layer_init_for_window(window);
    if (is_desktop) {
      gtk_layer_set_namespace(window, "fyrdesktop");
      gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_BOTTOM);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
      gtk_layer_set_exclusive_zone(window, -1);
      gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
      gtk_window_set_default_size(window, 1920, 1080);
      gtk_widget_set_size_request(GTK_WIDGET(window), 1920, 1080);
    } else {
      gtk_layer_set_namespace(window, "fyrtaskbar");
      gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
      gtk_layer_set_exclusive_zone(window, 56);
      gtk_layer_set_keyboard_mode(window,
                                  GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
      gtk_window_set_default_size(window, 1920, 56);
      gtk_widget_set_size_request(GTK_WIDGET(window), 1920, 56);
    }
  } else {
    gtk_window_set_default_size(window, 1280, 720);
  }
  gtk_widget_realize(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView *view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);

  // Enable transparency on the window
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);

  GdkScreen *gdk_screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual *visual = gdk_screen_get_rgba_visual(gdk_screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }

  // Remove any GTK shadows or margins
  gtk_window_set_decorated(window, FALSE);

  // To allow click-through for transparent areas on Wayland/X11 (if supported
  // by WM) Usually requires layer-shell, but we can try to make the window
  // transparent and see if the compositor passes events through (Sway might not
  // for regular windows).
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "fyrtaskbar/resize", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, fyr_method_call_cb, window,
                                            nullptr);

  if (!self->osd_overlay) {
    self->osd_overlay = new OsdOverlay();
  }
  self->osd_overlay->AttachMethodChannel(view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication *application,
                                                  gchar ***arguments,
                                                  int *exit_status) {
  MyApplication *self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
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

// Implements GApplication::startup.
static void my_application_startup(GApplication *application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication *application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject *object) {
  MyApplication *self = MY_APPLICATION(object);
  delete self->osd_overlay;
  self->osd_overlay = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass *klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self) {}

MyApplication *my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
