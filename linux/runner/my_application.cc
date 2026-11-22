#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;  // the one window; a second launch of Encore brings it back instead of opening another
  gboolean hidden;    // started with --hidden: only the tray icon until you open it
  FlMethodChannel* files;  // "encore/files": music files handed over by a second launch (encore song.flac)
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->hidden) gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Encore is already open (maybe only in the tray): show that window
  if (self->window != nullptr) {
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_present(self->window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  gtk_window_set_default_size(window, 1280, 820);
  gtk_window_set_icon_name(window, APPLICATION_ID);

  // If you want to use a header bar, uncomment the following lines.
  // Header bars are commonly used in GNOME based desktop environments and
  // allow additional widgets to be added to the title bar.
  // See https://docs.gtk.org/gtk3/class.HeaderBar.html
  // GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  // gtk_widget_show(GTK_WIDGET(header_bar));
  // gtk_header_bar_set_show_close_button(header_bar, TRUE);
  // gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));

  gtk_window_set_title(window, "Encore");

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->files = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)), "encore/files",
                                      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  for (char** a = self->dart_entrypoint_arguments; *a != nullptr; a++) {
    if (g_strcmp0(*a, "--hidden") == 0) self->hidden = TRUE;
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // Encore runs already and files were given (encore song.flac, or the file manager's "Open with"):
  // hand them to it (its open handler plays them) and this copy ends. Encore's first start gets them as
  // Dart arguments instead.
  if (g_application_get_is_remote(application)) {
    GPtrArray* files = g_ptr_array_new_with_free_func(g_object_unref);
    for (char** a = self->dart_entrypoint_arguments; *a != nullptr; a++) {
      if (g_str_has_prefix(*a, "--")) continue;
      g_ptr_array_add(files, g_file_new_for_commandline_arg(*a));
    }
    if (files->len > 0) {
      g_application_open(application, reinterpret_cast<GFile**>(files->pdata), files->len, "");
      g_ptr_array_unref(files);
      *exit_status = 0;
      return TRUE;
    }
    g_ptr_array_unref(files);
  }

  // Encore runs already: this activates it (shows its window) and this copy ends
  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::open: files handed over by a second launch. Encore shows its window and plays them.
static void my_application_open(GApplication* application, GFile** files, gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  my_application_activate(application);
  if (self->files == nullptr) return;
  g_autoptr(FlValue) paths = fl_value_new_list();
  for (gint i = 0; i < n_files; i++) {
    g_autofree gchar* path = g_file_get_path(files[i]);
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    fl_value_append_take(paths, fl_value_new_string(path != nullptr ? path : uri));
  }
  fl_method_channel_invoke_method(self->files, "open", paths, nullptr, nullptr, nullptr);
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->files);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // ENCORE_NON_UNIQUE=1: a second copy that doesn't hand over to the open one (for testing)
  GApplicationFlags flags = g_getenv("ENCORE_NON_UNIQUE") != nullptr ? G_APPLICATION_NON_UNIQUE
                                                                      : G_APPLICATION_DEFAULT_FLAGS;
  flags = static_cast<GApplicationFlags>(flags | G_APPLICATION_HANDLES_OPEN);  // files from a second launch
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}
