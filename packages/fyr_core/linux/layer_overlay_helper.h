#ifndef FYR_CORE_LAYER_OVERLAY_HELPER_H_
#define FYR_CORE_LAYER_OVERLAY_HELPER_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk-layer-shell.h>
#include <gtk/gtk.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace fyr_core {

struct LayerOverlayConfig {
  const char *layer_namespace = "fyroverlay";
  bool fullscreen = true;
  int width = 0;
  int height = 0;
  bool start_hidden = true;
  bool hide_on_focus_out = false;
};

struct LayerOverlayState {
  GtkWindow *window = nullptr;
  FlView *view = nullptr;
  LayerOverlayConfig config;
  bool visible = false;
};

inline bool ShouldStartShown(char *const *argv) {
  if (!argv) return false;
  for (int i = 0; argv[i] != nullptr; ++i) {
    if (std::strcmp(argv[i], "--show") == 0) {
      return true;
    }
  }
  return false;
}

inline GdkMonitor *FindMonitorForArg(const char *output_arg) {
  if (!output_arg || output_arg[0] == '\0') return nullptr;
  GdkDisplay *display = gdk_display_get_default();
  if (!display) return nullptr;

  int req_x = 0;
  int req_y = 0;
  bool has_coords = false;
  if (std::strchr(output_arg, ',') != nullptr) {
    char *end_ptr = nullptr;
    req_x = static_cast<int>(std::strtol(output_arg, &end_ptr, 10));
    if (end_ptr && *end_ptr == ',') {
      req_y = static_cast<int>(std::strtol(end_ptr + 1, nullptr, 10));
      has_coords = true;
    }
  }

  const int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; ++i) {
    GdkMonitor *mon = gdk_display_get_monitor(display, i);
    if (!mon) continue;
    if (has_coords) {
      GdkRectangle geom{};
      gdk_monitor_get_geometry(mon, &geom);
      if (geom.x == req_x && geom.y == req_y) {
        return mon;
      }
    } else {
      const char *model = gdk_monitor_get_model(mon);
      if (model && std::strcmp(model, output_arg) == 0) {
        return mon;
      }
    }
  }
  return nullptr;
}

inline void HideLayerOverlay(LayerOverlayState *state) {
  if (!state || !state->window) return;
  state->visible = false;
  gtk_layer_set_keyboard_mode(state->window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_widget_hide(GTK_WIDGET(state->window));
}

inline void ShowLayerOverlay(LayerOverlayState *state,
                             const char *output_name = nullptr) {
  if (!state || !state->window) return;
  state->visible = true;
  GdkMonitor *target = FindMonitorForArg(output_name);
  gtk_layer_set_monitor(state->window, target);
  gtk_layer_set_keyboard_mode(state->window,
                              GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
  gtk_widget_show(GTK_WIDGET(state->window));
  gtk_window_present(state->window);
  if (state->view) {
    gtk_widget_grab_focus(GTK_WIDGET(state->view));
  }
}

inline gboolean OnLayerOverlayDelete(GtkWidget * /*widget*/,
                                     GdkEvent * /*event*/,
                                     gpointer user_data) {
  HideLayerOverlay(static_cast<LayerOverlayState *>(user_data));
  return TRUE;
}

inline gboolean OnLayerOverlayFocusOut(GtkWidget * /*widget*/,
                                       GdkEventFocus * /*event*/,
                                       gpointer user_data) {
  auto *state = static_cast<LayerOverlayState *>(user_data);
  if (state && state->visible && state->config.hide_on_focus_out) {
    HideLayerOverlay(state);
  }
  return FALSE;
}

inline void ConfigureLayerOverlayWindow(GtkWindow *window,
                                        const LayerOverlayConfig &cfg) {
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen *screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual *visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }
  gtk_window_set_decorated(window, FALSE);

  GtkCssProvider *css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(
      css, "window, decoration { background: transparent; }", -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      screen, GTK_STYLE_PROVIDER(css),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(css);

  if (!cfg.fullscreen && cfg.width > 0 && cfg.height > 0) {
    gtk_window_set_default_size(window, cfg.width, cfg.height);
    gtk_widget_set_size_request(GTK_WIDGET(window), cfg.width, cfg.height);
    gtk_window_set_resizable(window, FALSE);
  }

  gtk_layer_init_for_window(window);
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
  gtk_layer_set_namespace(window, cfg.layer_namespace);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);

  if (cfg.fullscreen) {
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    gtk_layer_set_exclusive_zone(window, -1);
  } else {
    gtk_layer_set_exclusive_zone(window, 0);
  }
}

inline void AttachLayerOverlayChannel(LayerOverlayState *state,
                                      GtkWindow *window, FlView *view,
                                      const LayerOverlayConfig &cfg) {
  state->window = window;
  state->view = view;
  state->config = cfg;
  state->visible = !cfg.start_hidden;

  g_signal_connect(window, "delete-event", G_CALLBACK(OnLayerOverlayDelete),
                   state);
  if (cfg.hide_on_focus_out) {
    g_signal_connect(window, "focus-out-event",
                     G_CALLBACK(OnLayerOverlayFocusOut), state);
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "fyr/overlay_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel * /*channel*/, FlMethodCall *method_call,
         gpointer user_data) {
        auto *st = static_cast<LayerOverlayState *>(user_data);
        const gchar *method = fl_method_call_get_name(method_call);
        if (std::strcmp(method, "show") == 0) {
          const char *output = nullptr;
          FlValue *args = fl_method_call_get_args(method_call);
          if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
            if (FlValue *v = fl_value_lookup_string(args, "output")) {
              if (fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
                output = fl_value_get_string(v);
              }
            }
          }
          ShowLayerOverlay(st, output);
          g_autoptr(FlMethodResponse) resp =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
          fl_method_call_respond(method_call, resp, nullptr);
        } else if (std::strcmp(method, "hide") == 0) {
          HideLayerOverlay(st);
          g_autoptr(FlMethodResponse) resp =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
          fl_method_call_respond(method_call, resp, nullptr);
        } else {
          g_autoptr(FlMethodResponse) resp =
              FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
          fl_method_call_respond(method_call, resp, nullptr);
        }
      },
      state, nullptr);
}

// Forwards a command (e.g. "show") to an already-running overlay daemon so
// direct `--show` invocations reuse the warm instance instead of cold-spawning
// a duplicate Flutter engine.
inline bool ForwardToExistingOverlay(const char *app_name,
                                     const char *command) {
  const char *home = std::getenv("HOME");
  if (!home || !app_name || !command) return false;

  struct sockaddr_un addr {};
  addr.sun_family = AF_UNIX;
  int written = std::snprintf(addr.sun_path, sizeof(addr.sun_path),
                              "%s/.config/fyr/overlay-%s.sock", home, app_name);
  if (written <= 0 || static_cast<size_t>(written) >= sizeof(addr.sun_path)) {
    return false;
  }

  int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return false;

  bool sent = false;
  if (::connect(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) ==
      0) {
    std::string line = std::string(command) + "\n";
    ssize_t n = ::send(fd, line.c_str(), line.size(), MSG_NOSIGNAL);
    sent = n == static_cast<ssize_t>(line.size());
  }
  ::close(fd);
  return sent;
}

}  // namespace fyr_core

#endif  // FYR_CORE_LAYER_OVERLAY_HELPER_H_
