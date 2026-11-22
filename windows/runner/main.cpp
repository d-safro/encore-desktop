#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <cwchar>
#include <shellapi.h>
#include <string>

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
      // music files given (Explorer's "Open with", encore.exe song.flac): the running Encore plays them
      int argc = 0;
      wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
      std::wstring files;
      for (int i = 1; argv != nullptr && i < argc; i++) {
        if (wcsncmp(argv[i], L"--", 2) != 0) files += std::wstring(argv[i]) + L"\n";
      }
      if (argv != nullptr) ::LocalFree(argv);
      if (!files.empty()) {
        COPYDATASTRUCT data{0x454E4346, static_cast<DWORD>((files.size() + 1) * sizeof(wchar_t)),
                            const_cast<wchar_t*>(files.c_str())};
        ::SendMessageW(other, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data));
      }
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
