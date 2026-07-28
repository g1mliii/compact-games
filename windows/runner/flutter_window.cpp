#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT kResyncFlutterViewMessage = WM_APP + 0x51;

}  // namespace

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  // Initial window visibility is owned by the Dart/window_manager startup
  // policy so the app can show inactive and avoid stealing focus from an
  // already running game.

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_ && message == kResyncFlutterViewMessage) {
    if (IsIconic(hwnd)) {
      was_minimized_ = true;
      return 0;
    }
    const RECT frame = GetClientArea();
    const int width = frame.right - frame.left;
    const int height = frame.bottom - frame.top;
    const HWND flutter_view =
        flutter_controller_->view()->GetNativeWindow();
    // A same-size MoveWindow can be optimized away and leave Flutter's view
    // metrics stale. Nudge the child by one pixel, then restore the exact
    // client size in the same message turn to force a real metrics update
    // without changing the user's top-level window bounds.
    MoveWindow(flutter_view, frame.left, frame.top, width + 1, height + 1,
               FALSE);
    MoveWindow(flutter_view, frame.left, frame.top, width, height, TRUE);
    flutter_controller_->ForceRedraw();
    return 0;
  }

  if (message == WM_SIZE) {
    if (wparam == SIZE_MINIMIZED) {
      was_minimized_ = true;
    } else if (was_minimized_) {
      was_minimized_ = false;
      PostMessage(hwnd, kResyncFlutterViewMessage, 0, 0);
    }
  } else if (message == WM_SHOWWINDOW && wparam != FALSE) {
    if (IsIconic(hwnd)) {
      was_minimized_ = true;
    } else {
      // A never-shown or tray-hidden window can retain stale Flutter view
      // geometry. Resync after WM_SHOWWINDOW finishes so the HWND has its
      // final client bounds before Flutter renders the restored UI.
      PostMessage(hwnd, kResyncFlutterViewMessage, 0, 0);
    }
  }

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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
