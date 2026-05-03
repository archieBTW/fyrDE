#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <string.h>

static void do_minimize() {
    system("/usr/bin/swaymsg 'move scratchpad' >/dev/null 2>&1");
}

static void do_maximize() {
    system("/usr/bin/swaymsg 'fullscreen toggle' >/dev/null 2>&1");
}

void gtk_window_iconify(void *window) {
    static void (*real_iconify)(void*) = NULL;
    if (!real_iconify) real_iconify = dlsym(RTLD_NEXT, "gtk_window_iconify");
    if (real_iconify) real_iconify(window);
    do_minimize();
}

void gtk_window_minimize(void *window) {
    static void (*real_min)(void*) = NULL;
    if (!real_min) real_min = dlsym(RTLD_NEXT, "gtk_window_minimize");
    if (real_min) real_min(window);
    do_minimize();
}

void window_manager_minimize() {
    do_minimize();
}

void gtk_window_maximize(void *window) {
    static void (*real_max)(void*) = NULL;
    if (!real_max) real_max = dlsym(RTLD_NEXT, "gtk_window_maximize");
    if (real_max) real_max(window);
    do_maximize();
}

void gtk_window_unmaximize(void *window) {
    static void (*real_unmax)(void*) = NULL;
    if (!real_unmax) real_unmax = dlsym(RTLD_NEXT, "gtk_window_unmaximize");
    if (real_unmax) real_unmax(window);
    do_maximize();
}

void gtk_window_fullscreen(void *window) {
    static void (*real_full)(void*) = NULL;
    if (!real_full) real_full = dlsym(RTLD_NEXT, "gtk_window_fullscreen");
    if (real_full) real_full(window);
    do_maximize();
}

void gtk_window_unfullscreen(void *window) {
    static void (*real_unfull)(void*) = NULL;
    if (!real_unfull) real_unfull = dlsym(RTLD_NEXT, "gtk_window_unfullscreen");
    if (real_unfull) real_unfull(window);
    do_maximize();
}

void gtk_actionable_set_action_name(void *actionable, const char *action_name) {
    static void (*real_set)(void*, const char*) = NULL;
    static unsigned long (*signal_connect)(void*, const char*, void*, void*, void*, int) = NULL;
    
    if (!real_set) {
        real_set = dlsym(RTLD_NEXT, "gtk_actionable_set_action_name");
        signal_connect = dlsym(RTLD_DEFAULT, "g_signal_connect_data");
    }
    
    if (action_name && (strcmp(action_name, "window.minimize") == 0 || 
                        strcmp(action_name, "window.maximize") == 0 || 
                        strcmp(action_name, "window.toggle-maximized") == 0)) {
        if (signal_connect) {
            if (strcmp(action_name, "window.minimize") == 0) {
                signal_connect(actionable, "clicked", do_minimize, NULL, NULL, 0);
            } else {
                signal_connect(actionable, "clicked", do_maximize, NULL, NULL, 0);
            }
        }
        return; // Prevent GTK4 from binding the disabled action to the button
    }
    
    if (real_set) real_set(actionable, action_name);
}
