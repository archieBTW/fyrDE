#include "osd_overlay.h"

#include <cairo.h>
#include <gtk-layer-shell.h>
#include <pango/pangocairo.h>

#include <algorithm>
#include <cmath>
#include <cstring>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr int kOsdWidth = 280;
constexpr int kOsdHeight = 76;

void SetSourceArgb(cairo_t *cr, uint32_t argb, double alpha_scale = 1.0) {
  const double a = (((argb >> 24) & 0xFF) / 255.0) * alpha_scale;
  const double r = ((argb >> 16) & 0xFF) / 255.0;
  const double g = ((argb >> 8) & 0xFF) / 255.0;
  const double b = (argb & 0xFF) / 255.0;
  cairo_set_source_rgba(cr, r, g, b, a);
}

void DrawRoundedRect(cairo_t *cr, double x, double y, double w, double h,
                     double r) {
  const double radius = std::min(r, std::min(w, h) * 0.5);
  cairo_new_sub_path(cr);
  cairo_arc(cr, x + w - radius, y + radius, radius, -kPi * 0.5, 0.0);
  cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, kPi * 0.5);
  cairo_arc(cr, x + radius, y + h - radius, radius, kPi * 0.5, kPi);
  cairo_arc(cr, x + radius, y + radius, radius, kPi, kPi * 1.5);
  cairo_close_path(cr);
}

void DrawSpeakerIcon(cairo_t *cr, double cx, double cy, bool muted,
                     double fraction) {
  cairo_save(cr);
  cairo_translate(cr, cx, cy);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
  cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);

  // Speaker body
  cairo_move_to(cr, -10.0, -4.0);
  cairo_line_to(cr, -5.0, -4.0);
  cairo_line_to(cr, 1.0, -9.0);
  cairo_line_to(cr, 1.0, 9.0);
  cairo_line_to(cr, -5.0, 4.0);
  cairo_line_to(cr, -10.0, 4.0);
  cairo_close_path(cr);
  cairo_fill(cr);

  if (muted || fraction <= 0.001) {
    cairo_set_line_width(cr, 2.2);
    cairo_move_to(cr, 5.0, -5.0);
    cairo_line_to(cr, 12.0, 5.0);
    cairo_move_to(cr, 12.0, -5.0);
    cairo_line_to(cr, 5.0, 5.0);
    cairo_stroke(cr);
  } else {
    cairo_set_line_width(cr, 2.0);
    cairo_new_path(cr);
    cairo_arc(cr, 2.0, 0.0, 5.5, -kPi * 0.35, kPi * 0.35);
    cairo_stroke(cr);
    if (fraction > 0.45) {
      cairo_new_path(cr);
      cairo_arc(cr, 2.0, 0.0, 9.5, -kPi * 0.35, kPi * 0.35);
      cairo_stroke(cr);
    }
  }
  cairo_restore(cr);
}

void DrawMicIcon(cairo_t *cr, double cx, double cy, bool muted) {
  cairo_save(cr);
  cairo_translate(cr, cx, cy);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
  cairo_set_line_width(cr, 2.0);

  // Capsule
  DrawRoundedRect(cr, -4.0, -10.0, 8.0, 12.0, 4.0);
  cairo_fill(cr);

  // Cradle arc and stem
  cairo_new_path(cr);
  cairo_arc(cr, 0.0, -1.0, 7.5, 0.0, kPi);
  cairo_stroke(cr);
  cairo_move_to(cr, 0.0, 6.5);
  cairo_line_to(cr, 0.0, 10.5);
  cairo_move_to(cr, -4.5, 10.5);
  cairo_line_to(cr, 4.5, 10.5);
  cairo_stroke(cr);

  if (muted) {
    cairo_set_line_width(cr, 2.4);
    cairo_move_to(cr, -9.0, 9.0);
    cairo_line_to(cr, 9.0, -9.0);
    cairo_stroke(cr);
  }
  cairo_restore(cr);
}

void DrawBrightnessIcon(cairo_t *cr, double cx, double cy) {
  cairo_save(cr);
  cairo_translate(cr, cx, cy);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
  cairo_set_line_width(cr, 2.0);

  cairo_arc(cr, 0.0, 0.0, 4.8, 0.0, 2.0 * kPi);
  cairo_fill(cr);

  for (int i = 0; i < 8; ++i) {
    const double angle = i * (kPi * 0.25);
    const double x1 = std::cos(angle) * 7.8;
    const double y1 = std::sin(angle) * 7.8;
    const double x2 = std::cos(angle) * 10.8;
    const double y2 = std::sin(angle) * 10.8;
    cairo_move_to(cr, x1, y1);
    cairo_line_to(cr, x2, y2);
  }
  cairo_stroke(cr);
  cairo_restore(cr);
}

void DrawText(cairo_t *cr, const char *text, double x, double y, double width,
              PangoAlignment align, const char *font_desc_str) {
  PangoLayout *layout = pango_cairo_create_layout(cr);
  pango_layout_set_text(layout, text, -1);
  pango_layout_set_width(layout, static_cast<int>(width * PANGO_SCALE));
  pango_layout_set_alignment(layout, align);

  PangoFontDescription *desc =
      pango_font_description_from_string(font_desc_str);
  pango_layout_set_font_description(layout, desc);
  pango_font_description_free(desc);

  cairo_move_to(cr, x, y);
  pango_cairo_show_layout(cr, layout);
  g_object_unref(layout);
}

uint32_t GetArgUint32(FlValue *args, const char *key, uint32_t fallback) {
  FlValue *val = fl_value_lookup_string(args, key);
  if (!val) return fallback;
  if (fl_value_get_type(val) == FL_VALUE_TYPE_INT) {
    return static_cast<uint32_t>(fl_value_get_int(val));
  }
  return fallback;
}

}  // namespace

OsdOverlay::~OsdOverlay() {
  if (window_) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
}

void OsdOverlay::EnsureWindow() {
  if (window_) return;

  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window_), "fyrosd");
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_widget_set_size_request(window_, kOsdWidth, kOsdHeight);
  gtk_window_set_default_size(GTK_WINDOW(window_), kOsdWidth, kOsdHeight);
  gtk_widget_set_app_paintable(window_, TRUE);

  GdkScreen *screen = gtk_widget_get_screen(window_);
  GdkVisual *visual = gdk_screen_get_rgba_visual(screen);
  if (visual) {
    gtk_widget_set_visual(window_, visual);
  }

  gtk_layer_init_for_window(GTK_WINDOW(window_));
  gtk_layer_set_layer(GTK_WINDOW(window_), GTK_LAYER_SHELL_LAYER_OVERLAY);
  gtk_layer_set_namespace(GTK_WINDOW(window_), "fyrosd");
  gtk_layer_set_keyboard_mode(GTK_WINDOW(window_),
                              GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_layer_set_anchor(GTK_WINDOW(window_), GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
  gtk_layer_set_margin(GTK_WINDOW(window_), GTK_LAYER_SHELL_EDGE_BOTTOM, 108);
  gtk_layer_set_exclusive_zone(GTK_WINDOW(window_), 0);

  drawing_area_ = gtk_drawing_area_new();
  gtk_widget_set_size_request(drawing_area_, kOsdWidth, kOsdHeight);
  g_signal_connect(drawing_area_, "draw", G_CALLBACK(OsdOverlay::OnDraw), this);
  gtk_container_add(GTK_CONTAINER(window_), drawing_area_);
}

gboolean OsdOverlay::OnDraw(GtkWidget *widget, cairo_t *cr,
                            gpointer user_data) {
  OsdOverlay *self = static_cast<OsdOverlay *>(user_data);
  const OsdState &s = self->state_;

  const int w = gtk_widget_get_allocated_width(widget);
  const int h = gtk_widget_get_allocated_height(widget);

  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
  cairo_paint(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

  // Pill background
  DrawRoundedRect(cr, 1.0, 1.0, w - 2.0, h - 2.0, 18.0);
  SetSourceArgb(cr, s.bg_argb, 0.92);
  cairo_fill_preserve(cr);
  SetSourceArgb(cr, s.muted ? s.text_argb : s.accent_argb,
                s.muted ? 0.18 : 0.42);
  cairo_set_line_width(cr, 1.2);
  cairo_stroke(cr);

  // Left icon
  SetSourceArgb(cr, s.muted ? s.text_argb : s.accent_argb,
                s.muted ? 0.55 : 1.0);
  if (s.kind == "mic") {
    DrawMicIcon(cr, 32.0, h * 0.5, s.muted);
  } else if (s.kind == "brightness") {
    DrawBrightnessIcon(cr, 32.0, h * 0.5);
  } else {
    DrawSpeakerIcon(cr, 32.0, h * 0.5, s.muted, s.fraction);
  }

  // Title & Value text
  const double text_x = 56.0;
  const double text_w = w - text_x - 20.0;
  SetSourceArgb(cr, s.text_argb, 0.95);
  DrawText(cr, s.label.c_str(), text_x, 16.0, text_w * 0.68, PANGO_ALIGN_LEFT,
           "Sans Medium 10");
  SetSourceArgb(cr, s.text_argb, 0.72);
  DrawText(cr, s.value_text.c_str(), text_x, 16.0, text_w, PANGO_ALIGN_RIGHT,
           "Sans Bold 10");

  // Progress track
  const double bar_x = text_x;
  const double bar_y = 46.0;
  const double bar_w = text_w;
  const double bar_h = 7.0;
  DrawRoundedRect(cr, bar_x, bar_y, bar_w, bar_h, 3.5);
  SetSourceArgb(cr, s.text_argb, 0.14);
  cairo_fill(cr);

  // Active progress fill
  const double clamped = std::max(0.0, std::min(1.0, s.fraction));
  const double fill_w = s.muted ? 0.0 : bar_w * clamped;
  if (fill_w > 2.0) {
    DrawRoundedRect(cr, bar_x, bar_y, fill_w, bar_h, 3.5);
    SetSourceArgb(cr, s.accent_argb, 1.0);
    cairo_fill(cr);
  }

  return TRUE;
}

void OsdOverlay::Show(const OsdState &state) {
  state_ = state;
  EnsureWindow();
  gtk_widget_show_all(window_);
  gtk_widget_queue_draw(drawing_area_);
}

void OsdOverlay::Hide() {
  if (window_) {
    gtk_widget_hide(window_);
  }
}

void OsdOverlay::AttachMethodChannel(FlView *view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "fyrtaskbar/osd", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel * /*channel*/, FlMethodCall *method_call,
         gpointer user_data) {
        OsdOverlay *overlay = static_cast<OsdOverlay *>(user_data);
        const gchar *method = fl_method_call_get_name(method_call);
        if (std::strcmp(method, "show") == 0) {
          FlValue *args = fl_method_call_get_args(method_call);
          if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
            OsdState st;
            if (FlValue *v = fl_value_lookup_string(args, "kind")) {
              st.kind = fl_value_get_string(v);
            }
            if (FlValue *v = fl_value_lookup_string(args, "label")) {
              st.label = fl_value_get_string(v);
            }
            if (FlValue *v = fl_value_lookup_string(args, "valueText")) {
              st.value_text = fl_value_get_string(v);
            }
            if (FlValue *v = fl_value_lookup_string(args, "fraction")) {
              st.fraction = fl_value_get_float(v);
            }
            if (FlValue *v = fl_value_lookup_string(args, "muted")) {
              st.muted = fl_value_get_bool(v);
            }
            st.bg_argb = GetArgUint32(args, "bgArgb", st.bg_argb);
            st.text_argb = GetArgUint32(args, "textArgb", st.text_argb);
            st.accent_argb = GetArgUint32(args, "accentArgb", st.accent_argb);
            overlay->Show(st);
          }
          g_autoptr(FlMethodResponse) resp =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
          fl_method_call_respond(method_call, resp, nullptr);
        } else if (std::strcmp(method, "hide") == 0) {
          overlay->Hide();
          g_autoptr(FlMethodResponse) resp =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
          fl_method_call_respond(method_call, resp, nullptr);
        } else {
          g_autoptr(FlMethodResponse) resp =
              FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
          fl_method_call_respond(method_call, resp, nullptr);
        }
      },
      this, nullptr);
}
