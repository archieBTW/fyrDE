#ifndef WEBVIEW_CEF_TEXTURE_H_
#define WEBVIEW_CEF_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <cstdint>
#include <cstring>

struct WebviewCefTexture {
    FlPixelBufferTexture parent_instance;
    // Triple-buffered pixel storage:
    // - back_buffer: exclusively written by CEF UI thread outside the mutex
    // - front_buffer: latest completed frame awaiting hand-off under mutex
    // - render_buffer: exclusively read by Flutter render thread in copy_pixels
    uint8_t *back_buffer = nullptr;
    uint32_t back_width = 0;
    uint32_t back_height = 0;
    size_t back_capacity = 0;

    uint8_t *front_buffer = nullptr;
    uint32_t front_width = 0;
    uint32_t front_height = 0;
    size_t front_capacity = 0;
    bool has_new_frame = false;

    uint8_t *render_buffer = nullptr;
    uint32_t render_width = 0;
    uint32_t render_height = 0;
    size_t render_capacity = 0;

    GMutex mutex;
};

struct WebviewCefTextureClass {
    FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(WebviewCefTexture,
              webview_cef_texture,
              fl_pixel_buffer_texture_get_type())

#define WEBVIEW_CEF_TEXTURE(obj) \
    (G_TYPE_CHECK_INSTANCE_CAST((obj), webview_cef_texture_get_type(), WebviewCefTexture))

static void webview_cef_texture_submit_frame(WebviewCefTexture *texture,
                                             const void *bgra_src,
                                             int32_t width,
                                             int32_t height) {
    if (texture == nullptr || bgra_src == nullptr || width <= 0 || height <= 0) {
        return;
    }

    const size_t required = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    if (texture->back_capacity < required) {
        delete[] texture->back_buffer;
        texture->back_buffer = new uint8_t[required];
        texture->back_capacity = required;
    }
    texture->back_width = static_cast<uint32_t>(width);
    texture->back_height = static_cast<uint32_t>(height);

    // Convert BGRA -> RGBA into back_buffer completely outside the mutex so
    // Flutter's render thread is never stalled on full-frame pixel conversion.
    const uint32_t *__restrict src = static_cast<const uint32_t *>(bgra_src);
    uint32_t *__restrict dst = reinterpret_cast<uint32_t *>(texture->back_buffer);
    const size_t count = static_cast<size_t>(width) * static_cast<size_t>(height);
    for (size_t i = 0; i < count; ++i) {
        const uint32_t bgra = src[i];
        dst[i] = ((bgra & 0x00ff0000u) >> 16)
               | (bgra & 0xff00ff00u)
               | ((bgra & 0x000000ffu) << 16);
    }

    // O(1) pointer swap under lock.
    g_mutex_lock(&texture->mutex);
    std::swap(texture->back_buffer, texture->front_buffer);
    std::swap(texture->back_width, texture->front_width);
    std::swap(texture->back_height, texture->front_height);
    std::swap(texture->back_capacity, texture->front_capacity);
    texture->has_new_frame = true;
    g_mutex_unlock(&texture->mutex);
}

static gboolean webview_cef_texture_copy_pixels(FlPixelBufferTexture *texture,
                                                const uint8_t **out_buffer,
                                                uint32_t *width,
                                                uint32_t *height,
                                                GError **error) {
    WebviewCefTexture *_texture = WEBVIEW_CEF_TEXTURE(texture);
    if (_texture == nullptr) {
        return FALSE;
    }

    g_mutex_lock(&_texture->mutex);
    if (_texture->has_new_frame && _texture->front_buffer != nullptr) {
        std::swap(_texture->render_buffer, _texture->front_buffer);
        std::swap(_texture->render_width, _texture->front_width);
        std::swap(_texture->render_height, _texture->front_height);
        std::swap(_texture->render_capacity, _texture->front_capacity);
        _texture->has_new_frame = false;
    }
    g_mutex_unlock(&_texture->mutex);

    *out_buffer = _texture->render_buffer;
    *width = _texture->render_width;
    *height = _texture->render_height;
    return TRUE;
}

static void webview_cef_texture_finalize(GObject *object) {
    WebviewCefTexture *self = WEBVIEW_CEF_TEXTURE(object);
    g_mutex_clear(&self->mutex);
    delete[] self->back_buffer;
    delete[] self->front_buffer;
    delete[] self->render_buffer;
    self->back_buffer = nullptr;
    self->front_buffer = nullptr;
    self->render_buffer = nullptr;
    G_OBJECT_CLASS(webview_cef_texture_parent_class)->finalize(object);
}

static WebviewCefTexture *webview_cef_texture_new() {
    return WEBVIEW_CEF_TEXTURE(g_object_new(webview_cef_texture_get_type(), nullptr));
}

static void webview_cef_texture_class_init(WebviewCefTextureClass *klass) {
    FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = webview_cef_texture_copy_pixels;
    G_OBJECT_CLASS(klass)->finalize = webview_cef_texture_finalize;
}

static void webview_cef_texture_init(WebviewCefTexture *self) {
    g_mutex_init(&self->mutex);
    // Start with a valid 1x1 white pixel so copy_pixels always returns a live buffer.
    self->render_buffer = new uint8_t[4]{0xFF, 0xFF, 0xFF, 0xFF};
    self->render_width = 1;
    self->render_height = 1;
    self->render_capacity = 4;
}

#endif  // WEBVIEW_CEF_TEXTURE_H_
