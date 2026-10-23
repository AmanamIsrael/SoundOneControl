import AppKit
import Combine
import SwiftUI

@main
struct SoundOneControlApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var controller = AppServices.shared.controller

  var body: some Scene {
    Settings { EmptyView() }
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItemCoordinator: StatusItemCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let showSettings = CommandLine.arguments.contains("--show-settings")
    NSApp.setActivationPolicy(showSettings ? .regular : .accessory)
    AppServices.shared.shortcuts.register()
    if CommandLine.arguments.contains("--diagnose") {
      AppServices.shared.controller.runDiagnosticConnection()
    } else {
      AppServices.shared.controller.start()
    }
    statusItemCoordinator = StatusItemCoordinator(
      controller: AppServices.shared.controller,
      preferences: AppPreferences.shared
    )
    if showSettings { NSApp.activate(ignoringOtherApps: true) }
    if showSettings { statusItemCoordinator?.showSettings() }
  }
}

@MainActor
private final class StatusItemCoordinator: NSObject {
  private let controller: HeadphoneController
  private let preferences: AppPreferences
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var settingsWindow: NSWindow?
  private var cancellables: Set<AnyCancellable> = []

  init(controller: HeadphoneController, preferences: AppPreferences) {
    self.controller = controller
    self.preferences = preferences
    super.init()

    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.contentSize = NSSize(width: 360, height: 360)
    popover.contentViewController = NSHostingController(
      rootView: MenuBarContentView(
        controller: controller,
        openSettings: { [weak self] in self?.showSettings() }
      )
      .environmentObject(preferences)
    )

    controller.$showMenuBarItem
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] isVisible in self?.setStatusItemVisible(isVisible) }
      .store(in: &cancellables)
    controller.$connectionState
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] state in self?.updateStatusItemImage(for: state) }
      .store(in: &cancellables)
    setStatusItemVisible(controller.showMenuBarItem)
  }

  func showSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "SoundOne Control Settings"
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.toolbarStyle = .unified
      window.minSize = NSSize(width: 680, height: 500)
      window.setFrameAutosaveName("SoundOneControlSettings")
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(
        rootView: SettingsView(controller: controller)
          .environmentObject(preferences)
      )
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
    popover.performClose(nil)
  }

  @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu(relativeTo: sender)
    } else {
      togglePopover(sender)
    }
  }

  private func togglePopover(_ sender: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  private func showContextMenu(relativeTo button: NSStatusBarButton) {
    popover.performClose(nil)
    guard let statusItem else { return }
    let menu = NSMenu(title: "SoundOne Control")
    menu.addItem(
      withTitle: "Open Controls", action: #selector(openControlsFromMenu), keyEquivalent: "")
    menu.addItem(
      withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit SoundOne Control", action: #selector(quitFromMenu), keyEquivalent: "q")
    for item in menu.items { item.target = self }
    statusItem.menu = menu
    button.performClick(nil)
    statusItem.menu = nil
  }

  @objc private func openControlsFromMenu() {
    guard let button = statusItem?.button else { return }
    togglePopover(button)
  }

  @objc private func openSettingsFromMenu() {
    showSettings()
  }

  @objc private func refreshFromMenu() {
    controller.refresh()
  }

  @objc private func quitFromMenu() {
    NSApp.terminate(nil)
  }

  private func setStatusItemVisible(_ isVisible: Bool) {
    if isVisible, statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      item.button?.imagePosition = .imageOnly
      item.button?.toolTip = "SoundOne Control"
      item.button?.target = self
      item.button?.action = #selector(handleStatusItemClick(_:))
      item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
      statusItem = item
      updateStatusItemImage(for: controller.connectionState)
    } else if !isVisible, let statusItem {
      popover.performClose(nil)
      NSStatusBar.system.removeStatusItem(statusItem)
      self.statusItem = nil
    }
  }

  private func updateStatusItemImage(for state: HeadphoneController.ConnectionState) {
    statusItem?.button?.image = state == .connected ? MenuBarIcon.filled : MenuBarIcon.outlined
  }
}

@MainActor
private final class AppServices {
  static let shared = AppServices()
  let controller: HeadphoneController
  let shortcuts: GlobalShortcutManager

  private init() {
    let controller = HeadphoneController()
    self.controller = controller
    shortcuts = GlobalShortcutManager(controller: controller)
  }
}
