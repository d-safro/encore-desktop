#include <cstdio>
#include <cstring>

#include "my_application.h"

int main(int argc, char** argv) {
  // "encore --version": says which version this is and ends, without opening a window (no display needed)
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--version") == 0) {
      printf("Encore %s\n", FLUTTER_VERSION);
      return 0;
    }
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
