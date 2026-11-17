#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/joystick.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

// -----------------------------------------------------------------------------
// Minimal Libretro ABI Definitions (no external headers required)
// -----------------------------------------------------------------------------

#define RETRO_API_VERSION 1
#define RETRO_MEMORY_SAVE_RAM 0

#define RETRO_PIXEL_FORMAT_0RGB1555 0
#define RETRO_PIXEL_FORMAT_XRGB8888 1
#define RETRO_PIXEL_FORMAT_RGB565   2

#define RETRO_ENVIRONMENT_GET_CAN_DUPE          3
#define RETRO_ENVIRONMENT_SET_MESSAGE           6
#define RETRO_ENVIRONMENT_SHUTDOWN              7
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY  9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT      10
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS 11
#define RETRO_ENVIRONMENT_GET_VARIABLE          15
#define RETRO_ENVIRONMENT_SET_VARIABLES         16
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE   17
#define RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME   18
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE     27
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY    31
#define RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO    32
#define RETRO_ENVIRONMENT_SET_GEOMETRY          37
#define RETRO_ENVIRONMENT_GET_INPUT_BITMASKS    51
#define RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION 52

#define RETRO_DEVICE_JOYPAD 1
#define RETRO_DEVICE_ID_JOYPAD_MASK 256

struct retro_game_info {
  const char* path;
  const void* data;
  size_t size;
  const char* meta;
};

struct retro_system_info {
  const char* library_name;
  const char* library_version;
  const char* valid_extensions;
  bool need_fullpath;
  bool block_extract;
};

struct retro_game_geometry {
  unsigned base_width;
  unsigned base_height;
  unsigned max_width;
  unsigned max_height;
  float aspect_ratio;
};

struct retro_system_timing {
  double fps;
  double sample_rate;
};

struct retro_system_av_info {
  struct retro_game_geometry geometry;
  struct retro_system_timing timing;
};

typedef void (*retro_log_printf_t)(int level, const char* fmt, ...);
struct retro_log_callback {
  retro_log_printf_t log;
};

typedef bool (*retro_environment_t)(unsigned cmd, void* data);
typedef void (*retro_video_refresh_t)(const void* data, unsigned width,
                                      unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t* data, size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device,
                                       unsigned index, unsigned id);

// Core function pointers
typedef void (*fn_retro_init_t)(void);
typedef void (*fn_retro_deinit_t)(void);
typedef unsigned (*fn_retro_api_version_t)(void);
typedef void (*fn_retro_get_system_info_t)(struct retro_system_info* info);
typedef void (*fn_retro_get_system_av_info_t)(struct retro_system_av_info* info);
typedef void (*fn_retro_set_environment_t)(retro_environment_t);
typedef void (*fn_retro_set_video_refresh_t)(retro_video_refresh_t);
typedef void (*fn_retro_set_audio_sample_t)(retro_audio_sample_t);
typedef void (*fn_retro_set_audio_sample_batch_t)(retro_audio_sample_batch_t);
typedef void (*fn_retro_set_input_poll_t)(retro_input_poll_t);
typedef void (*fn_retro_set_input_state_t)(retro_input_state_t);
typedef void (*fn_retro_set_controller_port_device_t)(unsigned port,
                                                      unsigned device);
typedef bool (*fn_retro_load_game_t)(const struct retro_game_info* game);
typedef void (*fn_retro_unload_game_t)(void);
typedef void (*fn_retro_run_t)(void);
typedef void (*fn_retro_reset_t)(void);
typedef size_t (*fn_retro_serialize_size_t)(void);
typedef bool (*fn_retro_serialize_t)(void* data, size_t size);
typedef bool (*fn_retro_unserialize_t)(const void* data, size_t size);
typedef void* (*fn_retro_get_memory_data_t)(unsigned id);
typedef size_t (*fn_retro_get_memory_size_t)(unsigned id);

// -----------------------------------------------------------------------------
// PulseAudio Simple API via dlopen (zero compile-time link requirement)
// -----------------------------------------------------------------------------

typedef struct pa_simple pa_simple;
typedef struct {
  int format;
  uint32_t rate;
  uint8_t channels;
} pa_sample_spec_compat;

typedef struct {
  uint32_t maxlength;
  uint32_t tlength;
  uint32_t prebuf;
  uint32_t minreq;
  uint32_t fragsize;
} pa_buffer_attr_compat;

#define PA_STREAM_PLAYBACK 1
#define PA_SAMPLE_S16LE    3

typedef pa_simple* (*fn_pa_simple_new_t)(
    const char* server, const char* name, int dir, const char* dev,
    const char* stream_name, const pa_sample_spec_compat* ss,
    const void* map, const pa_buffer_attr_compat* attr, int* error);
typedef void (*fn_pa_simple_free_t)(pa_simple* s);
typedef int (*fn_pa_simple_write_t)(pa_simple* s, const void* data,
                                    size_t bytes, int* error);

static void* g_pa_lib = NULL;
static fn_pa_simple_new_t g_pa_new = NULL;
static fn_pa_simple_free_t g_pa_free = NULL;
static fn_pa_simple_write_t g_pa_write = NULL;
static pa_simple* g_pa_stream = NULL;
static uint32_t g_pa_rate = 0;

// Ring buffer for non-blocking stereo int16 audio
#define AUDIO_RING_FRAMES 16384
static int16_t g_audio_ring[AUDIO_RING_FRAMES * 2];
static volatile size_t g_ring_read = 0;
static volatile size_t g_ring_write = 0;
static pthread_mutex_t g_audio_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_audio_cond = PTHREAD_COND_INITIALIZER;
static pthread_t g_audio_thread;
static volatile bool g_audio_thread_running = false;
static volatile bool g_audio_stop_req = false;
static volatile float g_volume = 0.85f;
static volatile bool g_muted = false;

static void ensure_pulse_loaded(void) {
  if (g_pa_lib) return;
  g_pa_lib = dlopen("libpulse-simple.so.0", RTLD_LAZY);
  if (!g_pa_lib) g_pa_lib = dlopen("libpulse-simple.so", RTLD_LAZY);
  if (g_pa_lib) {
    g_pa_new = (fn_pa_simple_new_t)dlsym(g_pa_lib, "pa_simple_new");
    g_pa_free = (fn_pa_simple_free_t)dlsym(g_pa_lib, "pa_simple_free");
    g_pa_write = (fn_pa_simple_write_t)dlsym(g_pa_lib, "pa_simple_write");
  }
}

static void* audio_worker_fn(void* arg) {
  (void)arg;
  int16_t chunk[1024 * 2];
  while (!g_audio_stop_req) {
    pthread_mutex_lock(&g_audio_mutex);
    while (g_ring_read == g_ring_write && !g_audio_stop_req) {
      pthread_cond_wait(&g_audio_cond, &g_audio_mutex);
    }
    if (g_audio_stop_req) {
      pthread_mutex_unlock(&g_audio_mutex);
      break;
    }
    size_t avail = (g_ring_write - g_ring_read + AUDIO_RING_FRAMES) % AUDIO_RING_FRAMES;
    if (avail > 1024) avail = 1024;
    for (size_t i = 0; i < avail; i++) {
      size_t idx = (g_ring_read + i) % AUDIO_RING_FRAMES;
      chunk[i * 2] = g_audio_ring[idx * 2];
      chunk[i * 2 + 1] = g_audio_ring[idx * 2 + 1];
    }
    g_ring_read = (g_ring_read + avail) % AUDIO_RING_FRAMES;
    pa_simple* stream = g_pa_stream;
    pthread_mutex_unlock(&g_audio_mutex);

    if (stream && g_pa_write && avail > 0) {
      int err = 0;
      g_pa_write(stream, chunk, avail * 4, &err);
    }
  }
  return NULL;
}

static void init_audio_stream(uint32_t rate) {
  ensure_pulse_loaded();
  if (!g_pa_new || !g_pa_free || !g_pa_write) return;
  if (rate < 8000 || rate > 192000) rate = 44100;

  pthread_mutex_lock(&g_audio_mutex);
  if (g_pa_stream && g_pa_rate == rate) {
    pthread_mutex_unlock(&g_audio_mutex);
    return;
  }
  if (g_pa_stream) {
    g_pa_free(g_pa_stream);
    g_pa_stream = NULL;
  }
  pa_sample_spec_compat ss = {PA_SAMPLE_S16LE, rate, 2};
  pa_buffer_attr_compat attr = {
      (uint32_t)-1,
      rate * 4 / 20,  // ~50ms target latency
      (uint32_t)-1,
      (uint32_t)-1,
      (uint32_t)-1,
  };
  int err = 0;
  g_pa_stream = g_pa_new(NULL, "fyrEmu", PA_STREAM_PLAYBACK, NULL,
                         "Emulator Audio", &ss, NULL, &attr, &err);
  g_pa_rate = rate;
  g_ring_read = 0;
  g_ring_write = 0;
  pthread_mutex_unlock(&g_audio_mutex);

  if (g_pa_stream && !g_audio_thread_running) {
    g_audio_stop_req = false;
    if (pthread_create(&g_audio_thread, NULL, audio_worker_fn, NULL) == 0) {
      g_audio_thread_running = true;
    }
  }
}

static void shutdown_audio_stream(void) {
  if (g_audio_thread_running) {
    pthread_mutex_lock(&g_audio_mutex);
    g_audio_stop_req = true;
    pthread_cond_signal(&g_audio_cond);
    pthread_mutex_unlock(&g_audio_mutex);
    pthread_join(g_audio_thread, NULL);
    g_audio_thread_running = false;
  }
  pthread_mutex_lock(&g_audio_mutex);
  if (g_pa_stream && g_pa_free) {
    g_pa_free(g_pa_stream);
    g_pa_stream = NULL;
  }
  g_pa_rate = 0;
  g_ring_read = 0;
  g_ring_write = 0;
  pthread_mutex_unlock(&g_audio_mutex);
}

static void push_audio_frames(const int16_t* data, size_t frames) {
  if (!g_pa_stream || frames == 0) return;
  float vol = g_muted ? 0.0f : g_volume;

  pthread_mutex_lock(&g_audio_mutex);
  for (size_t i = 0; i < frames; i++) {
    size_t next = (g_ring_write + 1) % AUDIO_RING_FRAMES;
    if (next == g_ring_read) {
      // Buffer full (e.g. fast-forward): advance read head to avoid blocking
      g_ring_read = (g_ring_read + 1) % AUDIO_RING_FRAMES;
    }
    int32_t l = (int32_t)(data[i * 2] * vol);
    int32_t r = (int32_t)(data[i * 2 + 1] * vol);
    if (l > 32767) l = 32767;
    if (l < -32768) l = -32768;
    if (r > 32767) r = 32767;
    if (r < -32768) r = -32768;
    g_audio_ring[g_ring_write * 2] = (int16_t)l;
    g_audio_ring[g_ring_write * 2 + 1] = (int16_t)r;
    g_ring_write = next;
  }
  pthread_cond_signal(&g_audio_cond);
  pthread_mutex_unlock(&g_audio_mutex);
}

// -----------------------------------------------------------------------------
// Core State & Callbacks
// -----------------------------------------------------------------------------

static void* g_core_dl = NULL;
static bool g_game_loaded = false;
static char g_system_dir[512] = {0};
static char g_save_dir[512] = {0};
static char g_last_error[512] = {0};

static fn_retro_init_t c_init = NULL;
static fn_retro_deinit_t c_deinit = NULL;
static fn_retro_get_system_info_t c_get_sys_info = NULL;
static fn_retro_get_system_av_info_t c_get_av_info = NULL;
static fn_retro_set_environment_t c_set_env = NULL;
static fn_retro_set_video_refresh_t c_set_video = NULL;
static fn_retro_set_audio_sample_t c_set_audio = NULL;
static fn_retro_set_audio_sample_batch_t c_set_audio_batch = NULL;
static fn_retro_set_input_poll_t c_set_input_poll = NULL;
static fn_retro_set_input_state_t c_set_input_state = NULL;
static fn_retro_set_controller_port_device_t c_set_port_device = NULL;
static fn_retro_load_game_t c_load_game = NULL;
static fn_retro_unload_game_t c_unload_game = NULL;
static fn_retro_run_t c_run = NULL;
static fn_retro_reset_t c_reset = NULL;
static fn_retro_serialize_size_t c_serialize_size = NULL;
static fn_retro_serialize_t c_serialize = NULL;
static fn_retro_unserialize_t c_unserialize = NULL;
static fn_retro_get_memory_data_t c_get_mem_data = NULL;
static fn_retro_get_memory_size_t c_get_mem_size = NULL;

static int g_pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
static double g_fps = 60.0;
static double g_sample_rate = 44100.0;
static float g_aspect_ratio = 4.0f / 3.0f;

static uint8_t* g_rgba_buf = NULL;
static size_t g_rgba_cap = 0;
static unsigned g_video_w = 0;
static unsigned g_video_h = 0;
static uint64_t g_frame_seq = 0;
static pthread_mutex_t g_video_mutex = PTHREAD_MUTEX_INITIALIZER;

static uint32_t g_joypad_masks[4] = {0, 0, 0, 0};
static void* g_rom_buf = NULL;

static void retro_log_stub(int level, const char* fmt, ...) {
  (void)level;
  (void)fmt;
}

static bool env_callback(unsigned cmd, void* data) {
  switch (cmd) {
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
      if (data) *(bool*)data = true;
      return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
      if (data) {
        int fmt = *(int*)data;
        if (fmt == RETRO_PIXEL_FORMAT_0RGB1555 ||
            fmt == RETRO_PIXEL_FORMAT_XRGB8888 ||
            fmt == RETRO_PIXEL_FORMAT_RGB565) {
          g_pixel_format = fmt;
          return true;
        }
      }
      return false;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
      if (data) *(const char**)data = g_system_dir;
      return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
      if (data) *(const char**)data = g_save_dir;
      return true;
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
      if (data) {
        ((struct retro_log_callback*)data)->log = retro_log_stub;
        return true;
      }
      return false;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
      if (data) {
        const struct retro_system_av_info* av =
            (const struct retro_system_av_info*)data;
        if (av->timing.fps > 10.0) g_fps = av->timing.fps;
        if (av->timing.sample_rate > 4000.0) {
          g_sample_rate = av->timing.sample_rate;
          init_audio_stream((uint32_t)g_sample_rate);
        }
        if (av->geometry.aspect_ratio > 0.1f) {
          g_aspect_ratio = av->geometry.aspect_ratio;
        }
        return true;
      }
      return false;
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
      if (data) {
        const struct retro_game_geometry* g =
            (const struct retro_game_geometry*)data;
        if (g->aspect_ratio > 0.1f) g_aspect_ratio = g->aspect_ratio;
        return true;
      }
      return false;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
      return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
      if (data) *(bool*)data = false;
      return true;
    default:
      return false;
  }
}

static void video_refresh_cb(const void* data, unsigned width, unsigned height,
                             size_t pitch) {
  if (!data || width == 0 || height == 0) return;
  size_t needed = (size_t)width * (size_t)height * 4;

  pthread_mutex_lock(&g_video_mutex);
  if (needed > g_rgba_cap) {
    uint8_t* next = (uint8_t*)realloc(g_rgba_buf, needed);
    if (!next) {
      pthread_mutex_unlock(&g_video_mutex);
      return;
    }
    g_rgba_buf = next;
    g_rgba_cap = needed;
  }

  const uint8_t* src_row = (const uint8_t*)data;
  uint8_t* dst = g_rgba_buf;

  if (g_pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
    for (unsigned y = 0; y < height; y++) {
      const uint32_t* p = (const uint32_t*)src_row;
      for (unsigned x = 0; x < width; x++) {
        uint32_t c = p[x];
        *dst++ = (c >> 16) & 0xFF;  // R
        *dst++ = (c >> 8) & 0xFF;   // G
        *dst++ = c & 0xFF;          // B
        *dst++ = 0xFF;              // A
      }
      src_row += pitch;
    }
  } else if (g_pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
    for (unsigned y = 0; y < height; y++) {
      const uint16_t* p = (const uint16_t*)src_row;
      for (unsigned x = 0; x < width; x++) {
        uint16_t c = p[x];
        uint8_t r = (c >> 11) & 0x1F;
        uint8_t g = (c >> 5) & 0x3F;
        uint8_t b = c & 0x1F;
        *dst++ = (r << 3) | (r >> 2);
        *dst++ = (g << 2) | (g >> 4);
        *dst++ = (b << 3) | (b >> 2);
        *dst++ = 0xFF;
      }
      src_row += pitch;
    }
  } else {
    // 0RGB1555
    for (unsigned y = 0; y < height; y++) {
      const uint16_t* p = (const uint16_t*)src_row;
      for (unsigned x = 0; x < width; x++) {
        uint16_t c = p[x];
        uint8_t r = (c >> 10) & 0x1F;
        uint8_t g = (c >> 5) & 0x1F;
        uint8_t b = c & 0x1F;
        *dst++ = (r << 3) | (r >> 2);
        *dst++ = (g << 3) | (g >> 2);
        *dst++ = (b << 3) | (b >> 2);
        *dst++ = 0xFF;
      }
      src_row += pitch;
    }
  }

  g_video_w = width;
  g_video_h = height;
  g_frame_seq++;
  pthread_mutex_unlock(&g_video_mutex);
}

static void audio_sample_cb(int16_t left, int16_t right) {
  int16_t pair[2] = {left, right};
  push_audio_frames(pair, 1);
}

static size_t audio_sample_batch_cb(const int16_t* data, size_t frames) {
  push_audio_frames(data, frames);
  return frames;
}

static void input_poll_cb(void) {}

static int16_t input_state_cb(unsigned port, unsigned device, unsigned index,
                              unsigned id) {
  (void)index;
  if (port >= 4 || device != RETRO_DEVICE_JOYPAD) return 0;
  if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
    return (int16_t)(g_joypad_masks[port] & 0xFFFF);
  }
  if (id < 16) {
    return (g_joypad_masks[port] & (1u << id)) ? 1 : 0;
  }
  return 0;
}

// -----------------------------------------------------------------------------
// Exported FFI Core Control API
// -----------------------------------------------------------------------------

void fyremu_set_dirs(const char* sys_dir, const char* save_dir) {
  if (sys_dir) snprintf(g_system_dir, sizeof(g_system_dir), "%s", sys_dir);
  if (save_dir) snprintf(g_save_dir, sizeof(g_save_dir), "%s", save_dir);
}

const char* fyremu_get_last_error(void) {
  return g_last_error;
}

void fyremu_unload(void) {
  if (g_game_loaded && c_unload_game) {
    c_unload_game();
    g_game_loaded = false;
  }
  if (g_rom_buf) {
    free(g_rom_buf);
    g_rom_buf = NULL;
  }
  if (g_core_dl && c_deinit) {
    c_deinit();
  }
  if (g_core_dl) {
    dlclose(g_core_dl);
    g_core_dl = NULL;
  }
  shutdown_audio_stream();

  c_init = NULL;
  c_deinit = NULL;
  c_get_sys_info = NULL;
  c_get_av_info = NULL;
  c_set_env = NULL;
  c_set_video = NULL;
  c_set_audio = NULL;
  c_set_audio_batch = NULL;
  c_set_input_poll = NULL;
  c_set_input_state = NULL;
  c_set_port_device = NULL;
  c_load_game = NULL;
  c_unload_game = NULL;
  c_run = NULL;
  c_reset = NULL;
  c_serialize_size = NULL;
  c_serialize = NULL;
  c_unserialize = NULL;
  c_get_mem_data = NULL;
  c_get_mem_size = NULL;

  pthread_mutex_lock(&g_video_mutex);
  g_video_w = 0;
  g_video_h = 0;
  pthread_mutex_unlock(&g_video_mutex);
}

int fyremu_load(const char* core_path, const char* rom_path) {
  fyremu_unload();
  g_last_error[0] = '\0';
  g_pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;

  g_core_dl = dlopen(core_path, RTLD_LAZY);
  if (!g_core_dl) {
    snprintf(g_last_error, sizeof(g_last_error), "dlopen failed: %s",
             dlerror());
    return -1;
  }

  c_init = (fn_retro_init_t)dlsym(g_core_dl, "retro_init");
  c_deinit = (fn_retro_deinit_t)dlsym(g_core_dl, "retro_deinit");
  c_get_sys_info =
      (fn_retro_get_system_info_t)dlsym(g_core_dl, "retro_get_system_info");
  c_get_av_info = (fn_retro_get_system_av_info_t)dlsym(
      g_core_dl, "retro_get_system_av_info");
  c_set_env =
      (fn_retro_set_environment_t)dlsym(g_core_dl, "retro_set_environment");
  c_set_video =
      (fn_retro_set_video_refresh_t)dlsym(g_core_dl, "retro_set_video_refresh");
  c_set_audio =
      (fn_retro_set_audio_sample_t)dlsym(g_core_dl, "retro_set_audio_sample");
  c_set_audio_batch = (fn_retro_set_audio_sample_batch_t)dlsym(
      g_core_dl, "retro_set_audio_sample_batch");
  c_set_input_poll =
      (fn_retro_set_input_poll_t)dlsym(g_core_dl, "retro_set_input_poll");
  c_set_input_state =
      (fn_retro_set_input_state_t)dlsym(g_core_dl, "retro_set_input_state");
  c_set_port_device = (fn_retro_set_controller_port_device_t)dlsym(
      g_core_dl, "retro_set_controller_port_device");
  c_load_game = (fn_retro_load_game_t)dlsym(g_core_dl, "retro_load_game");
  c_unload_game =
      (fn_retro_unload_game_t)dlsym(g_core_dl, "retro_unload_game");
  c_run = (fn_retro_run_t)dlsym(g_core_dl, "retro_run");
  c_reset = (fn_retro_reset_t)dlsym(g_core_dl, "retro_reset");
  c_serialize_size =
      (fn_retro_serialize_size_t)dlsym(g_core_dl, "retro_serialize_size");
  c_serialize = (fn_retro_serialize_t)dlsym(g_core_dl, "retro_serialize");
  c_unserialize =
      (fn_retro_unserialize_t)dlsym(g_core_dl, "retro_unserialize");
  c_get_mem_data =
      (fn_retro_get_memory_data_t)dlsym(g_core_dl, "retro_get_memory_data");
  c_get_mem_size =
      (fn_retro_get_memory_size_t)dlsym(g_core_dl, "retro_get_memory_size");

  if (!c_init || !c_set_env || !c_load_game || !c_run || !c_get_sys_info ||
      !c_get_av_info) {
    snprintf(g_last_error, sizeof(g_last_error),
             "Invalid libretro core: missing required symbols");
    fyremu_unload();
    return -2;
  }

  c_set_env(env_callback);
  c_set_video(video_refresh_cb);
  if (c_set_audio) c_set_audio(audio_sample_cb);
  if (c_set_audio_batch) c_set_audio_batch(audio_sample_batch_cb);
  if (c_set_input_poll) c_set_input_poll(input_poll_cb);
  if (c_set_input_state) c_set_input_state(input_state_cb);

  c_init();

  struct retro_system_info sys_info = {0};
  c_get_sys_info(&sys_info);

  struct retro_game_info game = {0};
  game.path = rom_path;

  if (!sys_info.need_fullpath) {
    FILE* f = fopen(rom_path, "rb");
    if (!f) {
      snprintf(g_last_error, sizeof(g_last_error), "Cannot open ROM: %s",
               rom_path);
      fyremu_unload();
      return -3;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) {
      fclose(f);
      snprintf(g_last_error, sizeof(g_last_error), "Empty ROM file");
      fyremu_unload();
      return -4;
    }
    g_rom_buf = malloc((size_t)sz);
    if (!g_rom_buf) {
      fclose(f);
      snprintf(g_last_error, sizeof(g_last_error), "Out of memory reading ROM");
      fyremu_unload();
      return -5;
    }
    if (fread(g_rom_buf, 1, (size_t)sz, f) != (size_t)sz) {
      fclose(f);
      snprintf(g_last_error, sizeof(g_last_error), "Failed to read ROM bytes");
      fyremu_unload();
      return -6;
    }
    fclose(f);
    game.data = g_rom_buf;
    game.size = (size_t)sz;
  }

  if (!c_load_game(&game)) {
    snprintf(g_last_error, sizeof(g_last_error),
             "Core rejected ROM (%s)", rom_path);
    fyremu_unload();
    return -7;
  }
  g_game_loaded = true;

  if (c_set_port_device) {
    c_set_port_device(0, RETRO_DEVICE_JOYPAD);
  }

  struct retro_system_av_info av = {0};
  c_get_av_info(&av);
  g_fps = av.timing.fps > 10.0 ? av.timing.fps : 60.0;
  g_sample_rate =
      av.timing.sample_rate > 4000.0 ? av.timing.sample_rate : 44100.0;
  g_aspect_ratio = av.geometry.aspect_ratio > 0.1f
                       ? av.geometry.aspect_ratio
                       : ((av.geometry.base_height > 0)
                              ? ((float)av.geometry.base_width /
                                 (float)av.geometry.base_height)
                              : (4.0f / 3.0f));
  init_audio_stream((uint32_t)g_sample_rate);
  return 0;
}

void fyremu_run_frame(void) {
  if (g_game_loaded && c_run) {
    c_run();
  }
}

void fyremu_reset(void) {
  if (g_game_loaded && c_reset) {
    c_reset();
  }
}

void fyremu_set_joypad_mask(int port, uint32_t mask) {
  if (port >= 0 && port < 4) {
    g_joypad_masks[port] = mask;
  }
}

void fyremu_set_audio(float volume, int muted) {
  g_volume = volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume);
  g_muted = muted != 0;
}

double fyremu_get_fps(void) { return g_fps; }
double fyremu_get_aspect_ratio(void) { return (double)g_aspect_ratio; }
int fyremu_get_video_width(void) { return (int)g_video_w; }
int fyremu_get_video_height(void) { return (int)g_video_h; }
uint64_t fyremu_get_frame_seq(void) { return g_frame_seq; }

int fyremu_copy_frame_rgba(uint8_t* dst, int max_bytes) {
  pthread_mutex_lock(&g_video_mutex);
  size_t sz = (size_t)g_video_w * (size_t)g_video_h * 4;
  if (!g_rgba_buf || sz == 0 || (size_t)max_bytes < sz) {
    pthread_mutex_unlock(&g_video_mutex);
    return 0;
  }
  memcpy(dst, g_rgba_buf, sz);
  pthread_mutex_unlock(&g_video_mutex);
  return (int)sz;
}

// -----------------------------------------------------------------------------
// SRAM & Save States
// -----------------------------------------------------------------------------

int fyremu_save_srm(const char* path) {
  if (!g_game_loaded || !c_get_mem_data || !c_get_mem_size) return -1;
  size_t sz = c_get_mem_size(RETRO_MEMORY_SAVE_RAM);
  void* ptr = c_get_mem_data(RETRO_MEMORY_SAVE_RAM);
  if (!ptr || sz == 0) return 0;
  FILE* f = fopen(path, "wb");
  if (!f) return -2;
  fwrite(ptr, 1, sz, f);
  fclose(f);
  return 1;
}

int fyremu_load_srm(const char* path) {
  if (!g_game_loaded || !c_get_mem_data || !c_get_mem_size) return -1;
  size_t sz = c_get_mem_size(RETRO_MEMORY_SAVE_RAM);
  void* ptr = c_get_mem_data(RETRO_MEMORY_SAVE_RAM);
  if (!ptr || sz == 0) return 0;
  FILE* f = fopen(path, "rb");
  if (!f) return 0;
  size_t n = fread(ptr, 1, sz, f);
  fclose(f);
  return n > 0 ? 1 : 0;
}

int fyremu_save_state(const char* path) {
  if (!g_game_loaded || !c_serialize_size || !c_serialize) return -1;
  size_t sz = c_serialize_size();
  if (sz == 0) return -2;
  void* buf = malloc(sz);
  if (!buf) return -3;
  bool ok = c_serialize(buf, sz);
  if (!ok) {
    free(buf);
    return -4;
  }
  FILE* f = fopen(path, "wb");
  if (!f) {
    free(buf);
    return -5;
  }
  fwrite(buf, 1, sz, f);
  fclose(f);
  free(buf);
  return 0;
}

int fyremu_load_state(const char* path) {
  if (!g_game_loaded || !c_serialize_size || !c_unserialize) return -1;
  FILE* f = fopen(path, "rb");
  if (!f) return -2;
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (sz <= 0) {
    fclose(f);
    return -3;
  }
  void* buf = malloc((size_t)sz);
  if (!buf) {
    fclose(f);
    return -4;
  }
  if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
    fclose(f);
    free(buf);
    return -5;
  }
  fclose(f);
  bool ok = c_unserialize(buf, (size_t)sz);
  free(buf);
  return ok ? 0 : -6;
}

// -----------------------------------------------------------------------------
// Linux Joystick / Gamepad Hotplug & Polling (/dev/input/js0 .. js3)
// -----------------------------------------------------------------------------

#define MAX_CONTROLLERS 4
#define MAX_CTRL_BUTTONS 64
#define MAX_CTRL_AXES 32

typedef struct {
  int fd;
  bool connected;
  char name[128];
  uint8_t num_axes;
  uint8_t num_buttons;
  uint8_t buttons[MAX_CTRL_BUTTONS];
  int16_t axes[MAX_CTRL_AXES];
} FyrController;

static FyrController g_ctrls[MAX_CONTROLLERS] = {
    {.fd = -1}, {.fd = -1}, {.fd = -1}, {.fd = -1}};
static time_t g_last_scan_time = 0;

void fyremu_poll_controllers(void) {
  time_t now = time(NULL);
  bool rescan = (now - g_last_scan_time) >= 1;
  if (rescan) g_last_scan_time = now;

  for (int i = 0; i < MAX_CONTROLLERS; i++) {
    if (g_ctrls[i].fd < 0 && rescan) {
      char dev[32];
      snprintf(dev, sizeof(dev), "/dev/input/js%d", i);
      int fd = open(dev, O_RDONLY | O_NONBLOCK);
      if (fd >= 0) {
        g_ctrls[i].fd = fd;
        g_ctrls[i].connected = true;
        memset(g_ctrls[i].buttons, 0, sizeof(g_ctrls[i].buttons));
        memset(g_ctrls[i].axes, 0, sizeof(g_ctrls[i].axes));
        if (ioctl(fd, JSIOCGNAME(sizeof(g_ctrls[i].name)), g_ctrls[i].name) < 0) {
          snprintf(g_ctrls[i].name, sizeof(g_ctrls[i].name), "Controller %d",
                   i + 1);
        }
        ioctl(fd, JSIOCGAXES, &g_ctrls[i].num_axes);
        ioctl(fd, JSIOCGBUTTONS, &g_ctrls[i].num_buttons);
      }
    }

    if (g_ctrls[i].fd >= 0) {
      struct js_event ev;
      while (1) {
        ssize_t n = read(g_ctrls[i].fd, &ev, sizeof(ev));
        if (n == (ssize_t)sizeof(ev)) {
          uint8_t type = ev.type & ~JS_EVENT_INIT;
          if (type == JS_EVENT_BUTTON && ev.number < MAX_CTRL_BUTTONS) {
            g_ctrls[i].buttons[ev.number] = ev.value ? 1 : 0;
          } else if (type == JS_EVENT_AXIS && ev.number < MAX_CTRL_AXES) {
            g_ctrls[i].axes[ev.number] = ev.value;
          }
        } else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
          break;
        } else {
          close(g_ctrls[i].fd);
          g_ctrls[i].fd = -1;
          g_ctrls[i].connected = false;
          break;
        }
      }
    }
  }
}

int fyremu_get_controller_connected(int idx) {
  if (idx < 0 || idx >= MAX_CONTROLLERS) return 0;
  return g_ctrls[idx].connected ? 1 : 0;
}

void fyremu_get_controller_name(int idx, char* out, int max_len) {
  if (!out || max_len <= 0) return;
  if (idx < 0 || idx >= MAX_CONTROLLERS || !g_ctrls[idx].connected) {
    out[0] = '\0';
    return;
  }
  snprintf(out, (size_t)max_len, "%s", g_ctrls[idx].name);
}

int fyremu_get_controller_button_count(int idx) {
  if (idx < 0 || idx >= MAX_CONTROLLERS || !g_ctrls[idx].connected) return 0;
  return g_ctrls[idx].num_buttons;
}

int fyremu_get_controller_axis_count(int idx) {
  if (idx < 0 || idx >= MAX_CONTROLLERS || !g_ctrls[idx].connected) return 0;
  return g_ctrls[idx].num_axes;
}

int fyremu_get_controller_button(int idx, int btn) {
  if (idx < 0 || idx >= MAX_CONTROLLERS || !g_ctrls[idx].connected) return 0;
  if (btn < 0 || btn >= MAX_CTRL_BUTTONS) return 0;
  return g_ctrls[idx].buttons[btn];
}

int fyremu_get_controller_axis(int idx, int axis) {
  if (idx < 0 || idx >= MAX_CONTROLLERS || !g_ctrls[idx].connected) return 0;
  if (axis < 0 || axis >= MAX_CTRL_AXES) return 0;
  return g_ctrls[idx].axes[axis];
}
