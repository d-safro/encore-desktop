#include "flutter_window.h"

#include <optional>
#include <sstream>

#include <flutter/standard_method_codec.h>

#include "utils.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  files_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "encore/files",
      &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Encore's Dart side shows the window itself (window_manager), so that
  // "--hidden" (start in the tray) can keep it out of sight.

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  files_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      // a second start of Encore with music files (main.cpp): one path per line, UTF-16
      auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data != nullptr && data->dwData == 0x454E4346 && files_channel_ && data->cbData > 0) {
        std::wstring all(reinterpret_cast<const wchar_t*>(data->lpData), data->cbData / sizeof(wchar_t));
        flutter::EncodableList paths;
        std::wstringstream lines(all);
        std::wstring line;
        while (std::getline(lines, line)) {
          if (!line.empty()) paths.push_back(flutter::EncodableValue(Utf8FromUtf16(line.c_str())));
        }
        files_channel_->InvokeMethod("open", std::make_unique<flutter::EncodableValue>(paths));
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
