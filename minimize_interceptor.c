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

void gtk_widget_set_sensitive(void *widget, int sensitive) {
    static void (*real_set)(void*, int) = NULL;
    static int (*has_css_class)(void*, const char*) = NULL;
    static int init = 0;

    if (!init) {
        real_set = dlsym(RTLD_NEXT, "gtk_widget_set_sensitive");
        has_css_class = dlsym(RTLD_DEFAULT, "gtk_widget_has_css_class");
        init = 1;
    }

    if (!sensitive && has_css_class && widget) {
        if (has_css_class(widget, "minimize") || has_css_class(widget, "maximize")) {
            sensitive = 1;
        }
    }

    if (real_set) real_set(widget, sensitive);
}
