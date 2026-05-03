#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

void gtk_widget_set_sensitive(void *widget, int sensitive) {
    static void (*real_set)(void*, int) = NULL;
    if (!real_set) real_set = dlsym(RTLD_NEXT, "gtk_widget_set_sensitive");

    // We can't easily get the name without gtk_widget_get_name
    static const char* (*get_name)(void*) = NULL;
    if (!get_name) get_name = dlsym(RTLD_DEFAULT, "gtk_widget_get_name");
    
    static const char* (*get_css_name)(void*) = NULL;
    if (!get_css_name) get_css_name = dlsym(RTLD_DEFAULT, "gtk_widget_get_css_name");

    const char *name = get_name ? get_name(widget) : NULL;
    const char *css = get_css_name ? get_css_name(widget) : NULL;

    if ((name && strstr(name, "minimize")) || (css && strstr(css, "minimize"))) {
        sensitive = 1; // force sensitive
    }

    if (real_set) real_set(widget, sensitive);
}
