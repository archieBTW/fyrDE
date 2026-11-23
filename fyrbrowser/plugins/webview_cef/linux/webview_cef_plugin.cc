#include "include/webview_cef/webview_cef_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <atomic>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <webview_plugin.h>
#include "webview_cef_keyevent.h"
#include "webview_cef_texture.h"

#define WEBVIEW_CEF_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), webview_cef_plugin_get_type(), \
                              WebviewCefPlugin))

struct _WebviewCefPlugin
{
  GObject parent_instance;
  std::shared_ptr<webview_cef::WebviewPlugin> m_plugin;
  FlTextureRegistrar *m_textureRegister;
  FlMethodChannel *m_channel;
  std::shared_ptr<std::atomic<bool>> m_alive;
  int64_t m_window;
};

G_DEFINE_TYPE(WebviewCefPlugin, webview_cef_plugin, g_object_get_type())

std::unordered_map<int64_t, std::shared_ptr<webview_cef::WebviewPlugin>> webviewPlugins;
std::mutex webviewPluginsMutex;

class WebviewTextureRenderer : public webview_cef::WebviewTexture
{
public:
  WebviewTextureRenderer(FlTextureRegistrar *texture_register,
                         std::shared_ptr<std::atomic<bool>> plugin_alive)
      : register_(texture_register), alive_(std::move(plugin_alive))
  {
    texture = webview_cef_texture_new();
    g_object_ref(register_);
    fl_texture_registrar_register_texture(register_, FL_TEXTURE(texture));
    textureId = reinterpret_cast<int64_t>(texture);
  }

  virtual ~WebviewTextureRenderer()
  {
    active_.store(false, std::memory_order_release);
    FlTextureRegistrar *reg = register_;
    WebviewCefTexture *tex = texture;
    auto alive = alive_;
    register_ = nullptr;
    texture = nullptr;
    if (reg == nullptr || tex == nullptr) {
      return;
    }

    auto cleanup = [reg, tex, alive]() {
      if (alive && alive->load(std::memory_order_acquire)) {
        fl_texture_registrar_unregister_texture(reg, FL_TEXTURE(tex));
      }
      g_object_unref(tex);
      g_object_unref(reg);
    };

    if (g_main_context_is_owner(g_main_context_default())) {
      cleanup();
    } else {
      auto *fn = new std::function<void()>(std::move(cleanup));
      g_main_context_invoke(
          nullptr,
          [](gpointer user_data) -> gboolean {
            auto *cb = static_cast<std::function<void()> *>(user_data);
            (*cb)();
            delete cb;
            return G_SOURCE_REMOVE;
          },
          fn);
    }
  }

  virtual void onFrame(const void *buffer, int32_t width, int32_t height) override
  {
    if (!active_.load(std::memory_order_acquire) ||
        (alive_ && !alive_->load(std::memory_order_acquire)) ||
        texture == nullptr || register_ == nullptr) {
      return;
    }
    webview_cef_texture_submit_frame(texture, buffer, width, height);
    if (active_.load(std::memory_order_acquire) &&
        (!alive_ || alive_->load(std::memory_order_acquire))) {
      fl_texture_registrar_mark_texture_frame_available(register_, FL_TEXTURE(texture));
    }
  }

  FlTextureRegistrar *register_ = nullptr;
  WebviewCefTexture *texture = nullptr;
  std::shared_ptr<std::atomic<bool>> alive_;
  std::atomic<bool> active_{true};
};

static FlValue *encode_wavlue_to_flvalue(WValue *args)
{
  if (args == nullptr) {
    return fl_value_new_null();
  }
  WValueType type = webview_value_get_type(args);
  switch (type)
  {
  case Webview_Value_Type_Bool:
    return fl_value_new_bool(webview_value_get_bool(args));
  case Webview_Value_Type_Int:
    return fl_value_new_int(webview_value_get_int(args));
  case Webview_Value_Type_Float:
    return fl_value_new_float(webview_value_get_float(args));
  case Webview_Value_Type_Double:
    return fl_value_new_float(webview_value_get_double(args));
  case Webview_Value_Type_String:
    return fl_value_new_string(webview_value_get_string(args));
  case Webview_Value_Type_Uint8_List:
  {
    size_t len = webview_value_get_len(args);
    const uint8_t *val = webview_value_get_uint8_list(args);
    return fl_value_new_uint8_list(val, len);
  }
  case Webview_Value_Type_Int32_List:
  {
    size_t len = webview_value_get_len(args);
    const int32_t *val = webview_value_get_int32_list(args);
    return fl_value_new_int32_list(val, len);
  }
  case Webview_Value_Type_Int64_List:
  {
    size_t len = webview_value_get_len(args);
    const int64_t *val = webview_value_get_int64_list(args);
    return fl_value_new_int64_list(val, len);
  }
  case Webview_Value_Type_Float_List:
  {
    size_t len = webview_value_get_len(args);
    const float *val = webview_value_get_float_list(args);
    return fl_value_new_float32_list(val, len);
  }
  case Webview_Value_Type_Double_List:
  {
    size_t len = webview_value_get_len(args);
    const double *val = webview_value_get_double_list(args);
    return fl_value_new_float_list(val, len);
  }
  case Webview_Value_Type_List:
  {
    FlValue *ret = fl_value_new_list();
    size_t len = webview_value_get_len(args);
    for (size_t i = 0; i < len; i++)
    {
      FlValue *val = encode_wavlue_to_flvalue(webview_value_get_list_value(args, i));
      fl_value_append(ret, val);
      fl_value_unref(val);
    }
    return ret;
  }
  case Webview_Value_Type_Map:
  {
    FlValue *ret = fl_value_new_map();
    size_t len = webview_value_get_len(args);
    for (size_t i = 0; i < len; i++)
    {
      FlValue *key = encode_wavlue_to_flvalue(webview_value_get_key(args, i));
      FlValue *val = encode_wavlue_to_flvalue(webview_value_get_value(args, i));
      fl_value_set(ret, key, val);
      fl_value_unref(key);
      fl_value_unref(val);
    }
    return ret;
  }
  default:
    return fl_value_new_null();
  }
}

static WValue *encode_flvalue_to_wvalue(FlValue *args)
{
  if (args == nullptr) {
    return webview_value_new_null();
  }
  FlValueType argsType = fl_value_get_type(args);
  switch (argsType)
  {
  case FL_VALUE_TYPE_BOOL:
    return webview_value_new_bool(fl_value_get_bool(args));
  case FL_VALUE_TYPE_INT:
    return webview_value_new_int(fl_value_get_int(args));
  case FL_VALUE_TYPE_FLOAT:
    return webview_value_new_double(fl_value_get_float(args));
  case FL_VALUE_TYPE_STRING:
    return webview_value_new_string(fl_value_get_string(args));
  case FL_VALUE_TYPE_UINT8_LIST:
  {
    size_t len = fl_value_get_length(args);
    const uint8_t *val = fl_value_get_uint8_list(args);
    return webview_value_new_uint8_list(val, len);
  }
  case FL_VALUE_TYPE_INT32_LIST:
  {
    size_t len = fl_value_get_length(args);
    const int32_t *val = fl_value_get_int32_list(args);
    return webview_value_new_int32_list(val, len);
  }
  case FL_VALUE_TYPE_INT64_LIST:
  {
    size_t len = fl_value_get_length(args);
    const int64_t *val = fl_value_get_int64_list(args);
    return webview_value_new_int64_list(val, len);
  }
  case FL_VALUE_TYPE_FLOAT32_LIST:
  {
    size_t len = fl_value_get_length(args);
    const float *val = fl_value_get_float32_list(args);
    return webview_value_new_float_list(val, len);
  }
  case FL_VALUE_TYPE_FLOAT_LIST:
  {
    size_t len = fl_value_get_length(args);
    const double *val = fl_value_get_float_list(args);
    return webview_value_new_double_list(val, len);
  }
  case FL_VALUE_TYPE_LIST:
  {
    WValue *ret = webview_value_new_list();
    size_t len = fl_value_get_length(args);
    for (size_t i = 0; i < len; i++)
    {
      WValue *item = encode_flvalue_to_wvalue(fl_value_get_list_value(args, i));
      webview_value_append(ret, item);
      webview_value_unref(item);
    }
    return ret;
  }
  case FL_VALUE_TYPE_MAP:
  {
    WValue *ret = webview_value_new_map();
    size_t len = fl_value_get_length(args);
    for (size_t i = 0; i < len; i++)
    {
      WValue *key = encode_flvalue_to_wvalue(fl_value_get_map_key(args, i));
      WValue *val = encode_flvalue_to_wvalue(fl_value_get_map_value(args, i));
      webview_value_set(ret, key, val);
      webview_value_unref(key);
      webview_value_unref(val);
    }
    return ret;
  }
  default:
    return webview_value_new_null();
  }
}

struct MethodRespondData {
  FlMethodCall *method_call;
  int ret;
  FlValue *value;
  std::shared_ptr<std::atomic<bool>> alive;
};

static void respond_on_main_thread(FlMethodCall *method_call,
                                   int ret,
                                   FlValue *fl_val,
                                   const std::shared_ptr<std::atomic<bool>> &alive)
{
  if (alive && alive->load(std::memory_order_acquire)) {
    if (ret > 0) {
      fl_method_call_respond_success(method_call, fl_val, nullptr);
    } else if (ret < 0) {
      fl_method_call_respond_error(method_call, "error", "error", fl_val, nullptr);
    } else {
      fl_method_call_respond_not_implemented(method_call, nullptr);
    }
  }
  if (fl_val != nullptr) {
    fl_value_unref(fl_val);
  }
  g_object_unref(method_call);
}

// Called when a method call is received from Flutter.
static void webview_cef_plugin_handle_method_call(
    WebviewCefPlugin *self,
    FlMethodCall *method_call)
{
  const gchar *method = fl_method_call_get_name(method_call);
  WValue *encodeArgs = encode_flvalue_to_wvalue(fl_method_call_get_args(method_call));
  g_object_ref(method_call);
  auto alive = self->m_alive;
  self->m_plugin->HandleMethodCall(method, encodeArgs, [method_call, alive](int ret, WValue *responseArgs) {
    FlValue *fl_val = (ret != 0) ? encode_wavlue_to_flvalue(responseArgs) : nullptr;
    if (g_main_context_is_owner(g_main_context_default())) {
      respond_on_main_thread(method_call, ret, fl_val, alive);
    } else {
      auto *data = new MethodRespondData{method_call, ret, fl_val, alive};
      g_main_context_invoke(
          nullptr,
          [](gpointer user_data) -> gboolean {
            auto *d = static_cast<MethodRespondData *>(user_data);
            respond_on_main_thread(d->method_call, d->ret, d->value, d->alive);
            delete d;
            return G_SOURCE_REMOVE;
          },
          data);
    }
  });
  webview_value_unref(encodeArgs);
}

static void webview_cef_plugin_dispose(GObject *object)
{
  WebviewCefPlugin *self = WEBVIEW_CEF_PLUGIN(object);
  if (self->m_alive) {
    self->m_alive->store(false, std::memory_order_release);
  }
  bool shouldStopCef = false;
  {
    std::lock_guard<std::mutex> lock(webviewPluginsMutex);
    webviewPlugins.erase(self->m_window);
    shouldStopCef = webviewPlugins.empty();
  }
  self->m_plugin = nullptr;
  g_clear_object(&self->m_channel);
  if (shouldStopCef) {
    webview_cef::stopCEF();
  }
  G_OBJECT_CLASS(webview_cef_plugin_parent_class)->dispose(object);
}

static void webview_cef_plugin_class_init(WebviewCefPluginClass *klass)
{
  G_OBJECT_CLASS(klass)->dispose = webview_cef_plugin_dispose;
}

static void webview_cef_plugin_init(WebviewCefPlugin *self) {
  self->m_plugin = std::make_shared<webview_cef::WebviewPlugin>();
  self->m_alive = std::make_shared<std::atomic<bool>>(true);
  self->m_channel = nullptr;
  self->m_textureRegister = nullptr;
  self->m_window = 0;
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data)
{
  WebviewCefPlugin *plugin = WEBVIEW_CEF_PLUGIN(user_data);
  webview_cef_plugin_handle_method_call(plugin, method_call);
}

void webview_cef_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
  WebviewCefPlugin *plugin = WEBVIEW_CEF_PLUGIN(
      g_object_new(webview_cef_plugin_get_type(), nullptr));

  plugin->m_window = int64_t(fl_plugin_registrar_get_view(registrar));
  {
    std::lock_guard<std::mutex> lock(webviewPluginsMutex);
    webviewPlugins.emplace(plugin->m_window, plugin->m_plugin);
  }

  plugin->m_textureRegister = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel *channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "webview_cef",
                            FL_METHOD_CODEC(codec));
  plugin->m_channel = channel; // plugin owns the initial reference
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  auto alive = plugin->m_alive;

  plugin->m_plugin->setRunOnMainThreadFunc([alive](std::function<void()> task) {
    if (!alive || !alive->load(std::memory_order_acquire)) {
      return;
    }
    if (g_main_context_is_owner(g_main_context_default())) {
      task();
      return;
    }
    auto *payload = new std::pair<std::shared_ptr<std::atomic<bool>>, std::function<void()>>(
        alive, std::move(task));
    g_main_context_invoke(
        nullptr,
        [](gpointer user_data) -> gboolean {
          auto *p = static_cast<std::pair<std::shared_ptr<std::atomic<bool>>, std::function<void()>> *>(user_data);
          if (p->first && p->first->load(std::memory_order_acquire)) {
            p->second();
          }
          delete p;
          return G_SOURCE_REMOVE;
        },
        payload);
  });

  plugin->m_plugin->setLogNativeFunc([channel, alive](std::string message) {
    if (!alive || !alive->load(std::memory_order_acquire)) {
      return;
    }
    g_object_ref(channel);
    struct LogData {
      FlMethodChannel *ch;
      std::shared_ptr<std::atomic<bool>> alive;
      std::string msg;
    };
    auto *data = new LogData{channel, alive, std::move(message)};
    g_main_context_invoke(
        nullptr,
        [](gpointer user_data) -> gboolean {
          auto *d = static_cast<LogData *>(user_data);
          if (d->alive && d->alive->load(std::memory_order_acquire)) {
            g_autoptr(FlValue) args = fl_value_new_string(d->msg.c_str());
            fl_method_channel_invoke_method(d->ch, "onNativeLog", args, nullptr, nullptr, nullptr);
          }
          g_object_unref(d->ch);
          delete d;
          return G_SOURCE_REMOVE;
        },
        data);
  });

  plugin->m_plugin->setInvokeMethodFunc([channel, alive](std::string method, WValue *arguments) {
    if (!alive || !alive->load(std::memory_order_acquire)) {
      return;
    }
    FlValue *args = encode_wavlue_to_flvalue(arguments);
    g_object_ref(channel);
    struct InvokeData {
      FlMethodChannel *ch;
      std::shared_ptr<std::atomic<bool>> alive;
      std::string method;
      FlValue *args;
    };
    auto *data = new InvokeData{channel, alive, std::move(method), args};
    g_main_context_invoke(
        nullptr,
        [](gpointer user_data) -> gboolean {
          auto *d = static_cast<InvokeData *>(user_data);
          if (d->alive && d->alive->load(std::memory_order_acquire)) {
            fl_method_channel_invoke_method(d->ch, d->method.c_str(), d->args, nullptr, nullptr, nullptr);
          }
          fl_value_unref(d->args);
          g_object_unref(d->ch);
          delete d;
          return G_SOURCE_REMOVE;
        },
        data);
  });

  FlTextureRegistrar *texReg = plugin->m_textureRegister;
  plugin->m_plugin->setCreateTextureFunc([texReg, alive]() {
    std::shared_ptr<WebviewTextureRenderer> renderer =
        std::make_shared<WebviewTextureRenderer>(texReg, alive);
    return std::dynamic_pointer_cast<webview_cef::WebviewTexture>(renderer);
  });

  g_object_unref(plugin);
}

FLUTTER_PLUGIN_EXPORT int initCEFProcesses(int argc, char **argv)
{
  CefMainArgs main_args(argc, argv);
  return webview_cef::initCEFProcesses(main_args);
}

FLUTTER_PLUGIN_EXPORT gboolean processKeyEventForCEF(GtkWidget *widget, GdkEventKey *event, gpointer data)
{
  // FyrBrowser: Allow standard shortcuts to bypass CEF and reach Flutter
  if (event->keyval == GDK_KEY_F5) {
    return FALSE;
  }
  bool isControl = (event->state & GDK_CONTROL_MASK);
  if (isControl) {
    guint keyval = event->keyval;
    if (keyval == GDK_KEY_r || keyval == GDK_KEY_R ||
        keyval == GDK_KEY_t || keyval == GDK_KEY_T ||
        keyval == GDK_KEY_w || keyval == GDK_KEY_W ||
        keyval == GDK_KEY_l || keyval == GDK_KEY_L ||
        keyval == GDK_KEY_f || keyval == GDK_KEY_F ||
        keyval == GDK_KEY_plus || keyval == GDK_KEY_equal ||
        keyval == GDK_KEY_KP_Add ||
        keyval == GDK_KEY_minus || keyval == GDK_KEY_underscore ||
        keyval == GDK_KEY_KP_Subtract ||
        keyval == GDK_KEY_0 || keyval == GDK_KEY_KP_0 ||
        keyval == GDK_KEY_Tab || keyval == GDK_KEY_ISO_Left_Tab) {
      return FALSE;
    }
  }

  int64_t _id = int64_t(widget);
  std::shared_ptr<webview_cef::WebviewPlugin> plugin;
  {
    std::lock_guard<std::mutex> lock(webviewPluginsMutex);
    auto it = webviewPlugins.find(_id);
    if (it != webviewPlugins.end()) {
      plugin = it->second;
    }
  }

  if (plugin && plugin->getAnyBrowserFocused())
  {
    CefKeyEvent key_event = {};
    KeyboardCode windows_key_code = GdkEventToWindowsKeyCode(event);
    key_event.windows_key_code =
        GetWindowsKeyCodeWithoutLocation(windows_key_code);
    key_event.native_key_code = event->hardware_keycode;

    key_event.modifiers = GetCefStateModifiers(event->state);
    if (event->keyval >= GDK_KP_Space && event->keyval <= GDK_KP_9)
    {
      key_event.modifiers |= EVENTFLAG_IS_KEY_PAD;
    }
    if (key_event.modifiers & EVENTFLAG_ALT_DOWN)
    {
      key_event.is_system_key = true;
    }

    if (windows_key_code == VKEY_RETURN)
    {
      // Treat Enter as \r as expected by Blink/WebKit.
      key_event.unmodified_character = '\r';
    }
    else {
      key_event.unmodified_character =
          static_cast<int>(gdk_keyval_to_unicode(event->keyval));
    }

    // If ctrl key is pressed down, then control character shall be input.
    if (key_event.modifiers & EVENTFLAG_CONTROL_DOWN)
    {
      key_event.character = GetControlCharacter(
          windows_key_code, key_event.modifiers & EVENTFLAG_SHIFT_DOWN);
    }
    else
    {
      key_event.character = key_event.unmodified_character;
    }
    if (event->type == GDK_KEY_PRESS)
    {
      key_event.type = KEYEVENT_RAWKEYDOWN;
      plugin->sendKeyEvent(key_event);
      if (key_event.character != 0 &&
          !(key_event.modifiers & EVENTFLAG_CONTROL_DOWN)) {
        key_event.type = KEYEVENT_CHAR;
        plugin->sendKeyEvent(key_event);
      }
    }
    else
    {
      key_event.type = KEYEVENT_KEYUP;
      plugin->sendKeyEvent(key_event);
    }

    return TRUE;
  }
  // Let Flutter handle the key event when no CEF browser has focus.
  return FALSE;
}
