#ifndef FYR_OSD_OVERLAY_H_
#define FYR_OSD_OVERLAY_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <string>

struct OsdState {
  std::string kind = "volume";
  std::string label = "Volume";
  std::string value_text = "50%";
  double fraction = 0.5;
  bool muted = false;
  uint32_t bg_argb = 0xE6141418;
  uint32_t text_argb = 0xFFFFFFFF;
  uint32_t accent_argb = 0xFFE040FB;
};

class OsdOverlay {
 public:
  OsdOverlay() = default;
  ~OsdOverlay();

  void Show(const OsdState &state);
  void Hide();
  void AttachMethodChannel(FlView *view);

 private:
  void EnsureWindow();
  static gboolean OnDraw(GtkWidget *widget, cairo_t *cr, gpointer user_data);

  GtkWidget *window_ = nullptr;
  GtkWidget *drawing_area_ = nullptr;
  OsdState state_;
};

#endif  // FYR_OSD_OVERLAY_H_
