#include "wayland_scale.h"

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

// Why this exists
//
// On Wayland, Flutter (3.50) draws the app into a Wayland subsurface of the window. The subsurface's buffer scale
// is set once, when the subsurface is made, from the window's scale at that moment; the app's device pixel ratio
// follows the window's scale as it changes. GTK only learns a window's real scale once the window is on a screen,
// and it changes again when the window moves to a screen with another scale. When the two disagree, the app is
// drawn at half size in the top-left corner of the window with black around it (made at 2, window now at 1), or
// at double size and cut off (made at 1, window now at 2). With a laptop at 170 % and a screen at 100 % that's
// many starts and every move between them.
//
// Flutter bug: https://github.com/flutter/flutter/issues/196476 (FlSubsurfaceEGL never updates its buffer
// scale). Remove this file once the Flutter in use has the fix.
//
// The workaround: when the window's scale no longer matches the one the subsurface was made at, have Flutter's
// renderer make its subsurface again. The renderer makes it when it's realized, so it's unrealized and realized
// again; FlView also uses the renderer's realize to start the engine, so that handler is blocked meanwhile.
// Unrealizing is safe while the engine draws: the renderer holds its frame lock while it lets go of the
// subsurface (it's how the renderer is torn down anyway).
//
// Related: a window shown again after being hidden (the tray) gets a new Wayland surface, which GTK makes only
// after the window is mapped. The renderer looks for it on map and finds none, and makes its subsurface only on
// its next size change, at whatever scale the window has then, so it stays black until then. Here a new surface
// gets the renderer a fresh allocation right away, and so a subsurface at the current scale.
//
// Only Flutter's subsurface renderer (Wayland) is touched; under X11, or if a future Flutter renders differently,
// this finds nothing to do.

#ifdef GDK_WINDOWING_WAYLAND

namespace {

constexpr char kSubsurfaceRenderer[] = "FlViewRendererSubsurface";
constexpr char kWatchKey[] = "encore-scale-watch";

struct ScaleWatch {
  FlView* view;             // not owned: the watch lives on the renderer, which the view owns
  GtkWidget* renderer;      // not owned
  gpointer parent_surface;  // the window's wl_surface when the renderer last looked (its subsurface is on it)
  gint scale;               // the window's scale when the renderer made that subsurface (its buffer scale)
  guint idle;               // a pending fix
};

// Flutter's renderer widget inside the view (FlView › GtkEventBox › FlViewRendererSubsurface).
GtkWidget* find_renderer(GtkWidget* widget) {
  if (g_strcmp0(G_OBJECT_TYPE_NAME(widget), kSubsurfaceRenderer) == 0) return widget;
  if (!GTK_IS_CONTAINER(widget)) return nullptr;
  GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
  GtkWidget* found = nullptr;
  for (GList* l = children; l != nullptr && found == nullptr; l = l->next) {
    found = find_renderer(GTK_WIDGET(l->data));
  }
  g_list_free(children);
  return found;
}

// The Wayland surface of the window, which the subsurface hangs off (none while the window is hidden).
gpointer window_surface(GtkWidget* widget) {
  GdkWindow* window = gtk_widget_get_window(gtk_widget_get_toplevel(widget));
  if (window == nullptr || !GDK_IS_WAYLAND_WINDOW(window)) return nullptr;
  return gdk_wayland_window_get_wl_surface(window);
}

// Has the renderer make its subsurface again at the window's current scale.
void remake_subsurface(ScaleWatch* w, gint scale) {
  g_debug("Window scale is now %d, Flutter's subsurface was made at %d: making it again", scale, w->scale);
  guint realize = g_signal_lookup("realize", GTK_TYPE_WIDGET);
  auto match = static_cast<GSignalMatchType>(G_SIGNAL_MATCH_ID | G_SIGNAL_MATCH_DATA);
  g_signal_handlers_block_matched(w->renderer, match, realize, 0, nullptr, nullptr, w->view);
  gtk_widget_unrealize(w->renderer);
  gtk_widget_realize(w->renderer);
  g_signal_handlers_unblock_matched(w->renderer, match, realize, 0, nullptr, nullptr, w->view);
  w->parent_surface = window_surface(w->renderer);
  w->scale = scale;

  // unrealizing unmapped it; the new subsurface is sized and placed on the next allocation
  gtk_widget_map(w->renderer);
  gtk_widget_queue_resize(w->renderer);
}

gboolean fix_subsurface(gpointer data) {
  auto* w = static_cast<ScaleWatch*>(data);
  w->idle = 0;
  gpointer surface = window_surface(w->renderer);
  if (!gtk_widget_get_mapped(w->renderer) || surface == nullptr) return G_SOURCE_REMOVE;

  if (surface != w->parent_surface) {
    // a new surface the renderer hasn't seen yet: it makes its subsurface there on its next allocation
    g_debug("Window has a new surface: Flutter's subsurface follows it");
    gtk_widget_queue_resize(w->renderer);
    return G_SOURCE_REMOVE;
  }
  gint scale = gtk_widget_get_scale_factor(w->renderer);
  if (scale != w->scale) remake_subsurface(w, scale);
  return G_SOURCE_REMOVE;
}

void check(ScaleWatch* w) {
  if (w->idle != 0 || !gtk_widget_get_mapped(w->renderer)) return;
  gpointer surface = window_surface(w->renderer);
  if (surface == nullptr) return;
  if (surface != w->parent_surface || gtk_widget_get_scale_factor(w->renderer) != w->scale) {
    // after GTK and Flutter are done with this change (Flutter sends the new pixel ratio on the same signal)
    w->idle = g_idle_add(fix_subsurface, w);
  }
}

// The renderer (re)makes its subsurface whenever the window's surface isn't the one it last saw; it looks when
// it's realized, mapped and allocated. The same is checked here, right after it, to know which scale it used.
void after_renderer_looked(GtkWidget* renderer, gpointer data) {
  auto* w = static_cast<ScaleWatch*>(data);
  gpointer surface = window_surface(renderer);
  if (surface != w->parent_surface) {
    w->parent_surface = surface;
    w->scale = gtk_widget_get_scale_factor(renderer);
  }
  check(w);
}

void after_size_allocate(GtkWidget* renderer, GdkRectangle* allocation, gpointer data) {
  after_renderer_looked(renderer, data);
}

void on_scale_changed(GObject* renderer, GParamSpec* pspec, gpointer data) {
  check(static_cast<ScaleWatch*>(data));
}

// The window's configure events: the first one after it's shown comes once it has its (new) surface.
gboolean on_window_configure(GtkWidget* window, GdkEvent* event, gpointer renderer) {
  auto* w = static_cast<ScaleWatch*>(g_object_get_data(G_OBJECT(renderer), kWatchKey));
  if (w != nullptr) check(w);
  return FALSE;
}

void free_watch(gpointer data) {
  auto* w = static_cast<ScaleWatch*>(data);
  if (w->idle != 0) g_source_remove(w->idle);
  g_free(w);
}

}  // namespace

void keep_wayland_scale(FlView* view) {
  GtkWidget* renderer = find_renderer(GTK_WIDGET(view));
  GtkWidget* window = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (renderer == nullptr || !GTK_IS_WINDOW(window)) return;

  auto* w = g_new0(ScaleWatch, 1);
  w->view = view;
  w->renderer = renderer;
  w->parent_surface = window_surface(renderer);
  w->scale = gtk_widget_get_scale_factor(renderer);
  g_object_set_data_full(G_OBJECT(renderer), kWatchKey, w, free_watch);

  g_signal_connect_after(renderer, "realize", G_CALLBACK(after_renderer_looked), w);
  g_signal_connect_after(renderer, "map", G_CALLBACK(after_renderer_looked), w);
  g_signal_connect_after(renderer, "size-allocate", G_CALLBACK(after_size_allocate), w);
  g_signal_connect(renderer, "notify::scale-factor", G_CALLBACK(on_scale_changed), w);
  g_signal_connect_object(window, "configure-event", G_CALLBACK(on_window_configure), renderer,
                          static_cast<GConnectFlags>(0));
}

#else  // GTK without Wayland: nothing to do

void keep_wayland_scale(FlView* view) {}

#endif
