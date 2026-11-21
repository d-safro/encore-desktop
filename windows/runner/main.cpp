#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <cwchar>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // "encore.exe --version": says which version this is (in the console it was started from) and ends
  if (wcsstr(command_line, L"--version") != nullptr) {
    if (::AttachConsole(ATTACH_PARENT_PROCESS)) {
      FILE* out = nullptr;
      freopen_s(&out, "CONOUT$", "w", stdout);
      printf("Encore %s\n", FLUTTER_VERSION);
      fflush(stdout);
    }
    return EXIT_SUCCESS;
  }

  // Only one Encore runs at a time: a second start shows the first one's
  // window (it may be hidden in the tray) and ends.
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"dev.safro.encore.single");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND other = ::FindWindowW(L"ENCORE_WINDOW", nullptr);
    if (other != nullptr) {
      ::ShowWindow(other, ::IsIconic(other) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(other);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 820);
  if (!window.Create(L"Encore", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
