#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

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
