#include <lilv/lilv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void json_escape(const char* src, char* dst, size_t cap) {
  size_t j = 0;
  for (size_t i = 0; src && src[i] && j + 3 < cap; i++) {
    unsigned char c = (unsigned char)src[i];
    if (c == '"' || c == '\\') {
      dst[j++] = '\\';
      dst[j++] = (char)c;
    } else if (c >= 0x20) {
      dst[j++] = (char)c;
    }
  }
  dst[j] = '\0';
}

/* Scans installed LV2 plugins using liblilv-0 and writes a JSON array of
   descriptors (uri, name, category, control ports with min/max/default). */
int sb_lv2_scan(char* out_json, int out_cap) {
  if (!out_json || out_cap < 16) return -1;
  LilvWorld* world = lilv_world_new();
  if (!world) {
    snprintf(out_json, (size_t)out_cap, "[]");
    return 0;
  }
  lilv_world_load_all(world);
  const LilvPlugins* plugins = lilv_world_get_all_plugins(world);

  LilvNode* input_class = lilv_new_uri(world, LILV_URI_INPUT_PORT);
  LilvNode* output_class = lilv_new_uri(world, LILV_URI_OUTPUT_PORT);
  LilvNode* audio_class = lilv_new_uri(world, LILV_URI_AUDIO_PORT);
  LilvNode* control_class = lilv_new_uri(world, LILV_URI_CONTROL_PORT);

  int pos = snprintf(out_json, (size_t)out_cap, "[");
  int first_plugin = 1;

  LILV_FOREACH(plugins, it, plugins) {
    const LilvPlugin* p = lilv_plugins_get(plugins, it);
    const char* uri = lilv_node_as_uri(lilv_plugin_get_uri(p));
    LilvNode* name_node = lilv_plugin_get_name(p);
    const char* name = name_node ? lilv_node_as_string(name_node) : uri;
    const LilvPluginClass* pclass = lilv_plugin_get_class(p);
    const char* cat = pclass
        ? lilv_node_as_string(lilv_plugin_class_get_label(pclass))
        : "Effect";

    char esc_uri[512], esc_name[256], esc_cat[128];
    json_escape(uri, esc_uri, sizeof(esc_uri));
    json_escape(name, esc_name, sizeof(esc_name));
    json_escape(cat, esc_cat, sizeof(esc_cat));

    uint32_t num_ports = lilv_plugin_get_num_ports(p);
    int audio_in = 0, audio_out = 0;
    for (uint32_t i = 0; i < num_ports; i++) {
      const LilvPort* port = lilv_plugin_get_port_by_index(p, i);
      if (lilv_port_is_a(p, port, audio_class)) {
        if (lilv_port_is_a(p, port, input_class)) audio_in++;
        if (lilv_port_is_a(p, port, output_class)) audio_out++;
      }
    }

    if (audio_in > 0 && audio_out > 0 && pos + 512 < out_cap) {
      if (!first_plugin) pos += snprintf(out_json + pos, (size_t)(out_cap - pos), ",");
      first_plugin = 0;
      pos += snprintf(
          out_json + pos, (size_t)(out_cap - pos),
          "{\"uri\":\"%s\",\"name\":\"%s\",\"category\":\"%s\",\"audioIn\":%d,\"audioOut\":%d,\"controls\":[",
          esc_uri, esc_name, esc_cat, audio_in, audio_out);

      float* mins = (float*)calloc(num_ports, sizeof(float));
      float* maxs = (float*)calloc(num_ports, sizeof(float));
      float* defs = (float*)calloc(num_ports, sizeof(float));
      lilv_plugin_get_port_ranges_float(p, mins, maxs, defs);

      int first_ctrl = 1;
      for (uint32_t i = 0; i < num_ports && pos + 256 < out_cap; i++) {
        const LilvPort* port = lilv_plugin_get_port_by_index(p, i);
        if (lilv_port_is_a(p, port, control_class) &&
            lilv_port_is_a(p, port, input_class)) {
          LilvNode* p_name_node = lilv_port_get_name(p, port);
          const char* p_name = p_name_node ? lilv_node_as_string(p_name_node) : "Param";
          char esc_pn[128];
          json_escape(p_name, esc_pn, sizeof(esc_pn));
          if (!first_ctrl) pos += snprintf(out_json + pos, (size_t)(out_cap - pos), ",");
          first_ctrl = 0;
          pos += snprintf(
              out_json + pos, (size_t)(out_cap - pos),
              "{\"index\":%u,\"name\":\"%s\",\"min\":%g,\"max\":%g,\"default\":%g}",
              i, esc_pn, mins[i], maxs[i], defs[i]);
          if (p_name_node) lilv_node_free(p_name_node);
        }
      }
      pos += snprintf(out_json + pos, (size_t)(out_cap - pos), "]}");
      free(mins);
      free(maxs);
      free(defs);
    }

    if (name_node) lilv_node_free(name_node);
  }

  snprintf(out_json + pos, (size_t)(out_cap - pos), "]");

  lilv_node_free(input_class);
  lilv_node_free(output_class);
  lilv_node_free(audio_class);
  lilv_node_free(control_class);
  lilv_world_free(world);
  return 1;
}

/* Instantiates an LV2 plugin by URI, connects stereo/mono audio ports & normalized
   control values, processes num_frames samples, and frees cleanly. */
int sb_lv2_process_stereo(
    const char* plugin_uri,
    double sample_rate,
    int num_frames,
    float* left_buf,
    float* right_buf,
    const float* norm_controls,
    int num_controls) {
  if (!plugin_uri || num_frames <= 0 || !left_buf || !right_buf) return -1;
  LilvWorld* world = lilv_world_new();
  if (!world) return -2;
  lilv_world_load_all(world);

  LilvNode* uri_node = lilv_new_uri(world, plugin_uri);
  const LilvPlugins* plugins = lilv_world_get_all_plugins(world);
  const LilvPlugin* p = lilv_plugins_get_by_uri(plugins, uri_node);
  lilv_node_free(uri_node);
  if (!p) {
    lilv_world_free(world);
    return -3;
  }

  LilvInstance* inst = lilv_plugin_instantiate(p, sample_rate, NULL);
  if (!inst) {
    lilv_world_free(world);
    return -4;
  }

  LilvNode* input_class = lilv_new_uri(world, LILV_URI_INPUT_PORT);
  LilvNode* output_class = lilv_new_uri(world, LILV_URI_OUTPUT_PORT);
  LilvNode* audio_class = lilv_new_uri(world, LILV_URI_AUDIO_PORT);
  LilvNode* control_class = lilv_new_uri(world, LILV_URI_CONTROL_PORT);

  uint32_t num_ports = lilv_plugin_get_num_ports(p);
  float* mins = (float*)calloc(num_ports, sizeof(float));
  float* maxs = (float*)calloc(num_ports, sizeof(float));
  float* defs = (float*)calloc(num_ports, sizeof(float));
  float* ctrl_storage = (float*)calloc(num_ports, sizeof(float));
  lilv_plugin_get_port_ranges_float(p, mins, maxs, defs);

  float* in_l = (float*)malloc((size_t)num_frames * sizeof(float));
  float* in_r = (float*)malloc((size_t)num_frames * sizeof(float));
  float* dummy_out = (float*)calloc((size_t)num_frames, sizeof(float));
  memcpy(in_l, left_buf, (size_t)num_frames * sizeof(float));
  memcpy(in_r, right_buf, (size_t)num_frames * sizeof(float));

  int audio_in_idx = 0, audio_out_idx = 0, ctrl_idx = 0;
  for (uint32_t i = 0; i < num_ports; i++) {
    const LilvPort* port = lilv_plugin_get_port_by_index(p, i);
    if (lilv_port_is_a(p, port, audio_class)) {
      if (lilv_port_is_a(p, port, input_class)) {
        lilv_instance_connect_port(inst, i, audio_in_idx == 0 ? in_l : in_r);
        audio_in_idx++;
      } else if (lilv_port_is_a(p, port, output_class)) {
        if (audio_out_idx == 0) {
          lilv_instance_connect_port(inst, i, left_buf);
        } else if (audio_out_idx == 1) {
          lilv_instance_connect_port(inst, i, right_buf);
        } else {
          lilv_instance_connect_port(inst, i, dummy_out);
        }
        audio_out_idx++;
      }
    } else if (lilv_port_is_a(p, port, control_class)) {
      if (lilv_port_is_a(p, port, input_class)) {
        float val = defs[i];
        if (norm_controls && ctrl_idx < num_controls) {
          val = mins[i] + norm_controls[ctrl_idx] * (maxs[i] - mins[i]);
        }
        ctrl_storage[i] = val;
        ctrl_idx++;
      }
      lilv_instance_connect_port(inst, i, &ctrl_storage[i]);
    }
  }

  lilv_instance_activate(inst);
  lilv_instance_run(inst, (uint32_t)num_frames);
  if (audio_out_idx == 1) {
    memcpy(right_buf, left_buf, (size_t)num_frames * sizeof(float));
  }
  lilv_instance_deactivate(inst);
  lilv_instance_free(inst);

  free(in_l);
  free(in_r);
  free(dummy_out);
  free(mins);
  free(maxs);
  free(defs);
  free(ctrl_storage);
  lilv_node_free(input_class);
  lilv_node_free(output_class);
  lilv_node_free(audio_class);
  lilv_node_free(control_class);
  lilv_world_free(world);
  return 0;
}
