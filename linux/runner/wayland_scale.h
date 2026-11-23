#ifndef RUNNER_WAYLAND_SCALE_H_
#define RUNNER_WAYLAND_SCALE_H_

#include <flutter_linux/flutter_linux.h>

// Keeps Flutter's drawing at the window's scale on Wayland when the window's scale changes (it opens on, or is
// moved to, a screen with another scale), and after it's hidden and shown again. Call it once, after the view is
// added to its window. See wayland_scale.cc.
void keep_wayland_scale(FlView* view);

#endif  // RUNNER_WAYLAND_SCALE_H_
