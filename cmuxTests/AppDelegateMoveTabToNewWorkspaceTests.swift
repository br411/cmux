import AppKit
import CmuxControlSocket
import CmuxSettings
import CmuxTerminal
import Foundation
import Testing
import XCTest

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

@MainActor
@Suite(.serialized)
struct AppDelegateMoveTabToNewWorkspaceTests {
    @Test
    func moveSurfaceToNewWorkspaceCreatesSinglePanelWorkspaceFromPanelTitle() throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let sourceWorkspace = try XCTUnwrap(manager.selectedWorkspace)
        let sourcePaneId = try XCTUnwrap(sourceWorkspace.bonsplitController.allPaneIds.first)
        let remainingPanelId = try XCTUnwrap(sourceWorkspace.focusedTerminalPanel?.id)
        let movedPanel = try XCTUnwrap(sourceWorkspace.newTerminalSurface(inPane: sourcePaneId, focus: false))
        sourceWorkspace.setPanelCustomTitle(panelId: movedPanel.id, title: "Build logs")

        let originalWorkspaceCount = manager.tabs.count
        let result = try XCTUnwrap(app.moveSurfaceToNewWorkspace(
            panelId: movedPanel.id,
            focus: false,
            focusWindow: false
        ))

        let destinationWorkspace = try XCTUnwrap(manager.tabs.first { $0.id == result.destinationWorkspaceId })
        #expect(result.sourceWindowId == windowId)
        #expect(result.sourceWorkspaceId == sourceWorkspace.id)
        #expect(result.destinationWindowId == windowId)
        #expect(manager.tabs.count == originalWorkspaceCount + 1)
        #expect(destinationWorkspace.title == "Build logs")
        #expect(destinationWorkspace.panels.count == 1)
        #expect(destinationWorkspace.panels[movedPanel.id] != nil)
        #expect(sourceWorkspace.panels[movedPanel.id] == nil)
        #expect(sourceWorkspace.panels[remainingPanelId] != nil)
        #expect(result.paneId == destinationWorkspace.paneId(forPanelId: movedPanel.id)?.id)
    }

    @Test
    func moveSurfaceToNewWorkspaceFlushesPendingTitleBeforeDerivingDestinationTitle() async throws {
        let suiteName = "AppDelegateMoveSurfaceTitle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserDefaultsSettingsClient(defaults: defaults)
        let catalog = SettingCatalog()
        settings.set(true, for: catalog.terminal.titleUpdateCoalescingEnabled)
        settings.set(500, for: catalog.terminal.titleUpdateCoalescingMilliseconds)

        let scheduler = ManualCoalescerScheduler()
        let manager = TabManager(
            panelTitleUpdateCoalescer: NotificationBurstCoalescer(
                schedule: scheduler.schedule(delay:action:)
            ),
            settings: settings
        )
        let app = AppDelegate()
        let windowId = UUID()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let workspace = try XCTUnwrap(manager.selectedWorkspace)
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let remainingPanelId = try XCTUnwrap(workspace.focusedPanelId)
        let movedPanel = try XCTUnwrap(workspace.newTerminalSurface(inPane: paneId, focus: false))
        let movedTitle = "Moved Surface Title - grok"

        NotificationCenter.default.post(
            name: .ghosttyDidSetTitle,
            object: workspace.terminalPanel(for: movedPanel.id)?.surface,
            userInfo: [
                GhosttyNotificationKey.tabId: workspace.id,
                GhosttyNotificationKey.surfaceId: movedPanel.id,
                GhosttyNotificationKey.title: movedTitle,
            ]
        )

        await drainMainQueue()
        #expect(scheduler.delays == [0.5])
        #expect(workspace.panelTitles[movedPanel.id] != movedTitle)
        #expect(workspace.title != movedTitle)

        let result = try XCTUnwrap(app.moveSurfaceToNewWorkspace(
            panelId: movedPanel.id,
            focus: false,
            focusWindow: false
        ))
        let destinationWorkspace = try XCTUnwrap(manager.tabs.first { $0.id == result.destinationWorkspaceId })

        #expect(workspace.panels[movedPanel.id] == nil)
        #expect(workspace.panels[remainingPanelId] != nil)
        #expect(destinationWorkspace.customTitle == movedTitle)
        #expect(destinationWorkspace.title == movedTitle)
        #expect(destinationWorkspace.panelTitle(panelId: movedPanel.id) == movedTitle)

        scheduler.fire(at: 0)
        #expect(destinationWorkspace.title == movedTitle)
        #expect(destinationWorkspace.panelTitle(panelId: movedPanel.id) == movedTitle)
    }

    @Test
    func moveSurfaceToNewWorkspacePreservesTerminalTextBoxStateWhenDefaultsEnabled() throws {
        let defaults = UserDefaults.standard
        let showKey = TerminalTextBoxInputSettings.showOnNewTerminalsKey
        let focusKey = TerminalTextBoxInputSettings.focusOnNewTerminalsKey
        let previousShowValue = defaults.object(forKey: showKey)
        let previousFocusValue = defaults.object(forKey: focusKey)
        defer {
            if let previousShowValue {
                defaults.set(previousShowValue, forKey: showKey)
            } else {
                defaults.removeObject(forKey: showKey)
            }
            if let previousFocusValue {
                defaults.set(previousFocusValue, forKey: focusKey)
            } else {
                defaults.removeObject(forKey: focusKey)
            }
        }

        defaults.set(false, forKey: showKey)
        defaults.set(false, forKey: focusKey)

        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let sourceWorkspace = try XCTUnwrap(manager.selectedWorkspace)
        let sourcePaneId = try XCTUnwrap(sourceWorkspace.bonsplitController.allPaneIds.first)
        let movedPanel = try XCTUnwrap(sourceWorkspace.newTerminalSurface(inPane: sourcePaneId, focus: false))
        #expect(!movedPanel.isTextBoxActive)

        defaults.set(true, forKey: showKey)
        defaults.set(true, forKey: focusKey)

        let result = try XCTUnwrap(app.moveSurfaceToNewWorkspace(
            panelId: movedPanel.id,
            focus: false,
            focusWindow: false
        ))

        let destinationWorkspace = try XCTUnwrap(manager.tabs.first { $0.id == result.destinationWorkspaceId })
        let destinationPanel = try XCTUnwrap(destinationWorkspace.panels[movedPanel.id] as? TerminalPanel)
        #expect(!destinationPanel.isTextBoxActive)
        #expect(destinationPanel.preferredFocusIntentForActivation() != .terminal(.textBoxInput))
    }

    @Test
    func moveBrowserBonsplitTabToNewWorkspaceRequestsAddressBarFocus() throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let sourceWorkspace = try XCTUnwrap(manager.selectedWorkspace)
        let sourcePaneId = try XCTUnwrap(sourceWorkspace.bonsplitController.allPaneIds.first)
        let browserPanel = try XCTUnwrap(
            try sourceWorkspace.newBrowserSurface(
                inPane: sourcePaneId,
                url: XCTUnwrap(URL(string: "https://example.com")),
                focus: false
            )
        )
        let browserTabId = try XCTUnwrap(sourceWorkspace.surfaceIdFromPanelId(browserPanel.id)?.uuid)
        browserPanel.noteWebViewFocused()
        #expect(browserPanel.preferredFocusIntentForActivation() == .browser(.webView))

        let result = try XCTUnwrap(app.moveBonsplitTabToNewWorkspace(
            tabId: browserTabId,
            focus: true,
            focusWindow: false
        ))

        let destinationWorkspace = try XCTUnwrap(manager.tabs.first { $0.id == result.destinationWorkspaceId })
        let movedBrowserPanel = try XCTUnwrap(destinationWorkspace.panels[browserPanel.id] as? BrowserPanel)
        #expect(destinationWorkspace.panels.count == 1)
        #expect(!destinationWorkspace.panels.values.contains { $0 is TerminalPanel })
        #expect(destinationWorkspace.focusedPanelId == movedBrowserPanel.id)
        #expect(movedBrowserPanel.preferredFocusIntentForActivation() == .browser(.addressBar))
    }

    @Test
    func moveSurfaceToNewWorkspaceRejectsOnlyPanel() throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let sourceWorkspace = try XCTUnwrap(manager.selectedWorkspace)
        let onlyPanelId = try XCTUnwrap(sourceWorkspace.focusedTerminalPanel?.id)

        #expect(!app.canMoveSurfaceToNewWorkspace(panelId: onlyPanelId))
        #expect(app.moveSurfaceToNewWorkspace(panelId: onlyPanelId, focus: false, focusWindow: false) == nil)
        #expect(manager.tabs.count == 1)
        #expect(sourceWorkspace.panels[onlyPanelId] != nil)
    }

    @Test
    func moveTerminalBonsplitTabToExistingWorkspaceClosesEmptiedSourceWorkspace() throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let sourceWorkspace = try XCTUnwrap(manager.selectedWorkspace)
        let movedPanelId = try XCTUnwrap(sourceWorkspace.focusedTerminalPanel?.id)
        let movedBonsplitTabId = try XCTUnwrap(sourceWorkspace.surfaceIdFromPanelId(movedPanelId)?.uuid)
        let destinationWorkspace = manager.addWorkspace(title: "Operations", select: false)
        let destinationOriginalPanelId = try XCTUnwrap(destinationWorkspace.focusedTerminalPanel?.id)

        #expect(app.canMoveBonsplitTab(tabId: movedBonsplitTabId, toWorkspace: destinationWorkspace.id))
        #expect(app.moveBonsplitTab(
            tabId: movedBonsplitTabId,
            toWorkspace: destinationWorkspace.id,
            focus: false,
            focusWindow: false
        ))

        #expect(!manager.tabs.contains { $0.id == sourceWorkspace.id })
        #expect(manager.tabs.map(\.id) == [destinationWorkspace.id])
        #expect(sourceWorkspace.panels.isEmpty)
        #expect(destinationWorkspace.panels[movedPanelId] != nil)
        #expect(destinationWorkspace.panels[destinationOriginalPanelId] != nil)
        #expect(destinationWorkspace.panels.count == 2)
    }

    @Test
    func moveSurfaceToExistingWorkspaceClosesEmptiedSourceWorkspaceAndFocusesDestination() throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let sourceWorkspace = try XCTUnwrap(manager.selectedWorkspace)
        let movedPanelId = try XCTUnwrap(sourceWorkspace.focusedTerminalPanel?.id)
        let destinationWorkspace = manager.addWorkspace(title: "Operations", select: false)
        let destinationOriginalPanelId = try XCTUnwrap(destinationWorkspace.focusedTerminalPanel?.id)

        #expect(app.moveSurface(
            panelId: movedPanelId,
            toWorkspace: destinationWorkspace.id,
            focus: true,
            focusWindow: false
        ))

        #expect(!manager.tabs.contains { $0.id == sourceWorkspace.id })
        #expect(manager.tabs.map(\.id) == [destinationWorkspace.id])
        #expect(sourceWorkspace.panels.isEmpty)
        #expect(destinationWorkspace.panels[movedPanelId] != nil)
        #expect(destinationWorkspace.panels[destinationOriginalPanelId] != nil)
        #expect(destinationWorkspace.panels.count == 2)
        #expect(manager.selectedWorkspace?.id == destinationWorkspace.id)
        #expect(destinationWorkspace.focusedPanelId == movedPanelId)
    }

    @Test
    func moveRemoteTmuxWindowToNewWorkspaceKeepsSessionRoutingAfterRoundTrip() async throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let host = RemoteTmuxHost(destination: "user@workspace-transfer")
        let sessionName = "workspace-transfer"
        let connection = RemoteTmuxControlConnection(host: host, sessionName: sessionName)
        let pipe = Pipe()
        let writer = RemoteTmuxControlPipeWriter(
            handle: pipe.fileHandleForWriting,
            label: "remote-tmux-workspace-transfer-test",
            maxPendingBytes: 1 << 16,
            onFailure: {}
        )
        defer {
            app.remoteTmuxController.detach(host: host, sessionName: sessionName)
            writer.close()
            try? pipe.fileHandleForReading.close()
        }
        connection.installStdinWriterForTesting(writer)
        connection.handleMessageForTesting(.enter)
        connection.handleMessageForTesting(
            .commandResult(commandNumber: 0, lines: [], isError: false)
        )
        app.remoteTmuxController.cacheConnection(connection)
        #expect(try app.remoteTmuxController.mirrorSession(
            host: host,
            sessionName: sessionName,
            into: manager
        ))
        let sourceWorkspace = try #require(manager.tabs.first { $0.isRemoteTmuxMirror })
        let mirror = try #require(sourceWorkspace.remoteTmuxSessionMirror)

        connection.handleMessageForTesting(.commandResult(
            commandNumber: 1,
            lines: [
                "@1 f92f,80x24,0,0,0 f92f,80x24,0,0,0 [] one",
                "@2 e5d1,90x30,0,0,5 e5d1,90x30,0,0,5 [] two",
                "@3 f92f,80x24,0,0,6 f92f,80x24,0,0,6 [] three",
            ],
            isError: false
        ))
        while let kind = connection.pendingCommandKindsForTesting.first {
            let lines: [String]
            if case let .paneRects(tmuxWindowId, _) = kind {
                switch tmuxWindowId {
                case 1:
                    lines = ["%0 0 0 80 24 1 off :0 \"host\""]
                case 2:
                    lines = ["%5 0 0 90 30 0 off :1 \"host\""]
                default:
                    lines = ["%6 0 0 80 24 0 off :2 \"host\""]
                }
            } else {
                lines = []
            }
            connection.handleMessageForTesting(
                .commandResult(commandNumber: 2, lines: lines, isError: false)
            )
        }

        let movedPanelId = try #require(mirror.panelIdByWindow[1])
        let result = try #require(app.moveSurfaceToNewWorkspace(
            panelId: movedPanelId,
            focus: false,
            focusWindow: false
        ))
        let destinationWorkspace = try #require(
            manager.tabs.first { $0.id == result.destinationWorkspaceId }
        )
        let movedPanel = try #require(destinationWorkspace.terminalPanel(for: movedPanelId))
        #expect(mirror.workspaceIdOwningWindow(1) == destinationWorkspace.id)

        // Multiple remote windows may share one ordinary workspace while the
        // session root retains the final window and the control-stream owner.
        let secondMovedPanelId = try #require(mirror.panelIdByWindow[2])
        #expect(app.moveSurface(
            panelId: secondMovedPanelId,
            toWorkspace: destinationWorkspace.id,
            focus: false,
            focusWindow: false
        ))
        #expect(mirror.workspaceIdOwningWindow(2) == destinationWorkspace.id)
        #expect(destinationWorkspace.panels[secondMovedPanelId] != nil)
        #expect(destinationWorkspace.panels.count == 2)
        let movedTabId = try #require(destinationWorkspace.surfaceIdFromPanelId(movedPanelId))
        destinationWorkspace.bonsplitController.selectTab(movedTabId)
        #expect(destinationWorkspace.focusedPanelId == movedPanelId)

        // Workspace-only pane.create requests resolve the focused transferred
        // window-tab before validating options; unsupported local-only fields
        // must fail instead of being silently discarded by the tmux route.
        let unsupportedPaneCreate = TerminalController.shared.controlPaneCreate(
            routing: ControlRoutingSelectors(
                hasWindowIDParam: true,
                windowID: windowId,
                groupID: nil,
                workspaceID: destinationWorkspace.id,
                surfaceID: nil,
                paneID: nil
            ),
            inputs: ControlPaneCreateInputs(
                directionRaw: "right",
                typeRaw: nil,
                urlRaw: nil,
                workingDirectory: "/tmp/unsupported",
                initialCommand: nil,
                tmuxStartCommand: nil,
                startupEnvironment: [:],
                requestedSourceSurfaceID: nil,
                requestedFocus: false,
                hasInitialDividerPosition: false,
                initialDividerPositionRaw: nil
            )
        )
        #expect(unsupportedPaneCreate == .mirrorUnsupportedOptions(["working_directory"]))

        // The original mirror workspace remains the session-level control owner.
        // Its final remote window cannot be moved out and then silently cleaned up.
        let rootPanelId = try #require(mirror.panelIdByWindow[3])
        let rootTabId = try #require(sourceWorkspace.surfaceIdFromPanelId(rootPanelId)?.uuid)
        #expect(!app.canMoveBonsplitTab(
            tabId: rootTabId,
            toWorkspace: destinationWorkspace.id
        ))
        #expect(!app.moveSurface(
            panelId: rootPanelId,
            toWorkspace: destinationWorkspace.id,
            focus: false,
            focusWindow: false
        ))
        #expect(sourceWorkspace.panels[rootPanelId] != nil)
        #expect(mirror.workspaceIdOwningWindow(3) == sourceWorkspace.id)

        let firstOutput = Data("after-move".utf8)
        let beforeFirstOutput = movedPanel.surface.debugRemoteOutputByteCountForTesting()
        connection.handleMessageForTesting(.output(paneId: 0, data: firstOutput))
        #expect(
            movedPanel.surface.debugRemoteOutputByteCountForTesting()
                == beforeFirstOutput + firstOutput.count
        )

        connection.handleMessageForTesting(.subscriptionChanged(
            name: "cmux_cwd_0",
            value: "/tmp/after-move"
        ))
        #expect(destinationWorkspace.panelDirectories[movedPanelId] == "/tmp/after-move")
        #expect(!destinationWorkspace.allowsLocalDirectoryFallback(panelId: movedPanelId))
        #expect(destinationWorkspace.reportedPanelDirectory(panelId: movedPanelId) == "/tmp/after-move")
        #expect(destinationWorkspace.trustedRemoteCurrentDirectory == "/tmp/after-move")
        #expect(destinationWorkspace.usesRemoteDirectoryProvenance)
        #expect(sourceWorkspace.panelDirectories[movedPanelId] == nil)
        let destinationSnapshot = destinationWorkspace.sessionSnapshot(includeScrollback: false)
        #expect(destinationSnapshot.panels.isEmpty)
        if case let .pane(layoutPane) = destinationSnapshot.layout {
            #expect(layoutPane.panelIds.isEmpty)
        } else {
            Issue.record("single transferred tab snapshot did not prune to an empty pane")
        }
        connection.handleMessageForTesting(.windowRenamed(windowId: 1, name: "renamed-after-move"))
        #expect(destinationWorkspace.panelTitle(panelId: movedPanelId) == "renamed-after-move")

        let destinationPane = try #require(destinationWorkspace.paneId(forPanelId: movedPanelId))
        #expect(!destinationWorkspace.splitTabBar(
            destinationWorkspace.bonsplitController,
            shouldSplitPane: destinationPane,
            orientation: .vertical
        ))
        #expect(app.remoteTmuxController.handleMirrorTabCloseRequested(
            workspaceId: destinationWorkspace.id,
            panelId: movedPanelId
        ))
        #expect(destinationWorkspace.setPanelCustomTitle(
            panelId: movedPanelId,
            title: "outbound-after-move"
        ))

        // A later remote split must build and bind its pane surfaces in the
        // destination workspace rather than the original session workspace.
        let splitLayout = "cafe,80x24,0,0{40x24,0,0,0,39x24,41,0,4}"
        connection.handleMessageForTesting(.layoutChange(
            windowId: 1,
            layout: splitLayout,
            visibleLayout: splitLayout,
            zoomed: false
        ))
        while let kind = connection.pendingCommandKindsForTesting.first {
            let lines: [String]
            if case let .paneRects(tmuxWindowId, _) = kind, tmuxWindowId == 1 {
                lines = [
                    "%0 0 0 40 24 1 off :0 \"host\"",
                    "%4 41 0 39 24 0 off :0 \"host\"",
                ]
            } else {
                lines = []
            }
            connection.handleMessageForTesting(
                .commandResult(commandNumber: 3, lines: lines, isError: false)
            )
        }
        let destinationWindowMirror = try #require(
            destinationWorkspace.remoteTmuxWindowMirror(forPanelId: movedPanelId)
        )
        let addedPane = try #require(destinationWindowMirror.panel(forPane: 4))
        #expect(addedPane.workspaceId == destinationWorkspace.id)
        let splitOutput = Data("split-after-move".utf8)
        let beforeSplitOutput = addedPane.surface.debugRemoteOutputByteCountForTesting()
        connection.handleMessageForTesting(.output(paneId: 4, data: splitOutput))
        #expect(
            addedPane.surface.debugRemoteOutputByteCountForTesting()
                == beforeSplitOutput + splitOutput.count
        )

        // Selection and drag-style reordering remain remote tmux operations
        // after two window-tabs have been consolidated into one workspace.
        let secondMovedTabId = try #require(
            destinationWorkspace.surfaceIdFromPanelId(secondMovedPanelId)
        )
        destinationWorkspace.bonsplitController.selectTab(secondMovedTabId)
        #expect(destinationWorkspace.focusedPanelId == secondMovedPanelId)
        #expect(destinationWorkspace.reorderSurface(
            panelId: secondMovedPanelId,
            toIndex: 0,
            focus: false
        ))
        #expect(connection.windowOrder == [2, 1, 3])
        let destinationPaneId = try #require(
            destinationWorkspace.paneId(forPanelId: secondMovedPanelId)
        )
        #expect(
            destinationWorkspace.bonsplitController.tabs(inPane: destinationPaneId)
                .compactMap { destinationWorkspace.panelIdFromSurfaceId($0.id) }
                == [secondMovedPanelId, movedPanelId]
        )

        #expect(app.moveSurface(
            panelId: movedPanelId,
            toWorkspace: sourceWorkspace.id,
            focus: false,
            focusWindow: false
        ))
        #expect(mirror.workspaceIdOwningWindow(1) == sourceWorkspace.id)
        let returnedWindowMirror = try #require(
            sourceWorkspace.remoteTmuxWindowMirror(forPanelId: movedPanelId)
        )
        let returnedPane = try #require(returnedWindowMirror.panel(forPane: 4))
        #expect(returnedPane === addedPane)
        #expect(returnedPane.workspaceId == sourceWorkspace.id)
        let sourceFlashToken = sourceWorkspace.tmuxWorkspaceFlashToken
        let destinationFlashToken = destinationWorkspace.tmuxWorkspaceFlashToken
        returnedPane.onRequestWorkspacePaneFlash?(.notificationDismiss)
        #expect(sourceWorkspace.tmuxWorkspaceFlashToken == sourceFlashToken + 1)
        #expect(sourceWorkspace.tmuxWorkspaceFlashPanelId == returnedPane.id)
        #expect(destinationWorkspace.tmuxWorkspaceFlashToken == destinationFlashToken)
        let returnedOutput = Data("after-return".utf8)
        let beforeReturnedOutput = returnedPane.surface.debugRemoteOutputByteCountForTesting()
        connection.handleMessageForTesting(.output(paneId: 4, data: returnedOutput))
        #expect(
            returnedPane.surface.debugRemoteOutputByteCountForTesting()
                == beforeReturnedOutput + returnedOutput.count
        )

        // Closing the native window that owns an ordinary destination
        // re-projects every still-live remote window in its session root before
        // the destination manager and workspace are released.
        let cleanupWorkspace = manager.addWorkspace(title: "cleanup", select: false)
        #expect(app.moveSurface(
            panelId: movedPanelId,
            toWorkspace: cleanupWorkspace.id,
            focus: false,
            focusWindow: false
        ))
        app.remoteTmuxController.handleWindowWorkspacesClosed(
            workspaceIds: [cleanupWorkspace.id]
        )
        let rehomedPanelId = try #require(mirror.panelIdByWindow[1])
        #expect(sourceWorkspace.panels[rehomedPanelId] != nil)
        #expect(mirror.workspaceIdOwningWindow(1) == sourceWorkspace.id)
        manager.closeWorkspace(cleanupWorkspace)
        #expect(!manager.tabs.contains { $0.id == cleanupWorkspace.id })

        // Close Pane in a mixed ordinary workspace kills its moved remote
        // window, closes local tabs in that pane, and leaves sibling panes
        // intact until tmux's authoritative %window-close removes the wrapper.
        let mixedCloseWorkspace = manager.addWorkspace(title: "mixed-close", select: false)
        let mixedLocalPanelId = try #require(mixedCloseWorkspace.focusedPanelId)
        let mixedPaneId = try #require(mixedCloseWorkspace.paneId(forPanelId: mixedLocalPanelId))
        let mixedSibling = try #require(mixedCloseWorkspace.newTerminalSplit(
            from: mixedLocalPanelId,
            orientation: .vertical,
            focus: false
        ))
        #expect(app.moveSurface(
            panelId: rehomedPanelId,
            toWorkspace: mixedCloseWorkspace.id,
            targetPane: mixedPaneId,
            focus: false,
            focusWindow: false
        ))
        #expect(!mixedCloseWorkspace.bonsplitController.closePane(mixedPaneId))
        await drainMainQueue()
        #expect(mixedCloseWorkspace.panels[mixedLocalPanelId] == nil)
        #expect(mixedCloseWorkspace.panels[rehomedPanelId] != nil)
        #expect(mixedCloseWorkspace.panels[mixedSibling.id] != nil)
        connection.handleMessageForTesting(.windowClose(windowId: 1))
        #expect(mixedCloseWorkspace.panels[rehomedPanelId] == nil)
        #expect(!mixedCloseWorkspace.bonsplitController.allPaneIds.contains(mixedPaneId))
        #expect(mixedCloseWorkspace.panels[mixedSibling.id] != nil)

        // Close Other Tabs uses the same per-panel remote dispatch. The moved
        // window remains projected until tmux acknowledges the kill; explicit
        // detach then removes it without disturbing the selected local tab.
        let bulkCloseWorkspace = manager.addWorkspace(title: "bulk-close", select: false)
        let bulkLocalPanelId = try #require(bulkCloseWorkspace.focusedPanelId)
        #expect(app.moveSurface(
            panelId: secondMovedPanelId,
            toWorkspace: bulkCloseWorkspace.id,
            focus: false,
            focusWindow: false
        ))
        manager.focusTab(
            bulkCloseWorkspace.id,
            surfaceId: bulkLocalPanelId,
            suppressFlash: true
        )
        manager.confirmCloseHandler = { _, _, _ in true }
        manager.closeOtherTabsInFocusedPaneWithConfirmation()
        manager.confirmCloseHandler = nil
        #expect(bulkCloseWorkspace.panels[secondMovedPanelId] != nil)
        #expect(mirror.workspaceIdOwningWindow(2) == bulkCloseWorkspace.id)

        app.remoteTmuxController.detach(host: host, sessionName: sessionName)
        #expect(bulkCloseWorkspace.panels[secondMovedPanelId] == nil)
        #expect(bulkCloseWorkspace.panels[bulkLocalPanelId] != nil)

        writer.close()
        let commandData = try pipe.fileHandleForReading.readToEnd() ?? Data()
        let commands = String(decoding: commandData, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
        #expect(commands.contains("rename-window -t @1 'outbound-after-move'"))
        #expect(commands.contains("kill-window -t @1"))
        #expect(commands.contains("split-window -v -t @1.%0"))
        #expect(commands.contains("kill-window -t @2"))
    }

    @Test
    func movingPinnedRemoteWindowAcrossPanesSynchronizesItsSession() throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let sessionA = try attachRemoteSession(
            app: app,
            manager: manager,
            destination: "user@pin-order-a",
            sessionName: "pin-order-a",
            windows: [
                (windowId: 1, paneId: 10, name: "a-one"),
                (windowId: 2, paneId: 11, name: "a-root"),
            ]
        )
        let sessionB = try attachRemoteSession(
            app: app,
            manager: manager,
            destination: "user@pin-order-b",
            sessionName: "pin-order-b",
            windows: [
                (windowId: 1, paneId: 20, name: "b-one"),
                (windowId: 2, paneId: 21, name: "b-two"),
                (windowId: 3, paneId: 22, name: "b-root"),
            ]
        )
        defer {
            sessionA.tearDown(app: app)
            sessionB.tearDown(app: app)
        }

        let destination = manager.addWorkspace(title: "mixed sessions", select: false)
        let localPanelId = try #require(destination.focusedPanelId)
        let targetPane = try #require(destination.paneId(forPanelId: localPanelId))
        let aOne = try #require(sessionA.mirror.panelIdByWindow[1])
        let bOne = try #require(sessionB.mirror.panelIdByWindow[1])
        let bTwo = try #require(sessionB.mirror.panelIdByWindow[2])

        #expect(app.moveSurface(
            panelId: aOne,
            toWorkspace: destination.id,
            targetPane: targetPane,
            focus: false,
            focusWindow: false
        ))
        #expect(app.moveSurface(
            panelId: bOne,
            toWorkspace: destination.id,
            targetPane: targetPane,
            focus: false,
            focusWindow: false
        ))
        #expect(app.moveSurface(
            panelId: bTwo,
            toWorkspace: destination.id,
            targetPane: targetPane,
            splitTarget: (orientation: .vertical, insertFirst: false),
            focus: false,
            focusWindow: false
        ))
        let bTwoPane = try #require(destination.paneId(forPanelId: bTwo))
        #expect(bTwoPane != targetPane)

        destination.setPanelPinned(panelId: aOne, pinned: true)
        destination.setPanelPinned(panelId: bTwo, pinned: true)
        #expect(sessionA.connection.windowOrder == [1, 2])
        #expect(sessionB.connection.windowOrder == [1, 2, 3])

        #expect(destination.moveSurface(
            panelId: bTwo,
            toPane: targetPane,
            atIndex: 1,
            focus: false
        ))

        let destinationOrder = destination.bonsplitController.tabs(inPane: targetPane)
            .compactMap { destination.panelIdFromSurfaceId($0.id) }
        #expect(destinationOrder.filter { $0 == bOne || $0 == bTwo } == [bTwo, bOne])
        #expect(sessionA.connection.windowOrder == [1, 2])
        #expect(sessionB.connection.windowOrder == [2, 1, 3])
    }

    @Test
    func inboundRemoteReorderReconcilesEachDestinationPaneIndependently() throws {
        let app = AppDelegate()
        let windowId = UUID()
        let manager = TabManager()
        app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
        defer { app.unregisterMainWindowContextForTesting(windowId: windowId) }

        let session = try attachRemoteSession(
            app: app,
            manager: manager,
            destination: "user@inbound-pane-order",
            sessionName: "inbound-pane-order",
            windows: [
                (windowId: 1, paneId: 10, name: "one"),
                (windowId: 2, paneId: 11, name: "two"),
                (windowId: 3, paneId: 12, name: "three"),
                (windowId: 4, paneId: 13, name: "root"),
            ]
        )
        defer { session.tearDown(app: app) }

        let destination = manager.addWorkspace(title: "destination", select: false)
        let localPanelId = try #require(destination.focusedPanelId)
        let targetPane = try #require(destination.paneId(forPanelId: localPanelId))
        let one = try #require(session.mirror.panelIdByWindow[1])
        let two = try #require(session.mirror.panelIdByWindow[2])
        let three = try #require(session.mirror.panelIdByWindow[3])

        #expect(app.moveSurface(
            panelId: one,
            toWorkspace: destination.id,
            targetPane: targetPane,
            focus: false,
            focusWindow: false
        ))
        #expect(app.moveSurface(
            panelId: two,
            toWorkspace: destination.id,
            targetPane: targetPane,
            focus: false,
            focusWindow: false
        ))
        #expect(app.moveSurface(
            panelId: three,
            toWorkspace: destination.id,
            targetPane: targetPane,
            splitTarget: (orientation: .vertical, insertFirst: false),
            focus: false,
            focusWindow: false
        ))
        let secondPane = try #require(destination.paneId(forPanelId: three))
        #expect(secondPane != targetPane)
        let remoteOrderBefore = destination.bonsplitController.tabs(inPane: targetPane)
            .compactMap { destination.panelIdFromSurfaceId($0.id) }
            .filter { $0 == one || $0 == two }
        #expect(remoteOrderBefore == [one, two])

        session.connection.handleMessageForTesting(.windowAdd(windowId: 99))
        session.connection.handleMessageForTesting(.commandResult(
            commandNumber: 100,
            lines: [
                "@2 f92f,80x24,0,0,11 f92f,80x24,0,0,11 [] two",
                "@1 f92f,80x24,0,0,10 f92f,80x24,0,0,10 [] one",
                "@3 f92f,80x24,0,0,12 f92f,80x24,0,0,12 [] three",
                "@4 f92f,80x24,0,0,13 f92f,80x24,0,0,13 [] root",
            ],
            isError: false
        ))

        var commandNumber = 101
        while let kind = session.connection.pendingCommandKindsForTesting.first {
            let lines: [String]
            if case let .paneRects(tmuxWindowId, _) = kind {
                let paneId = [1: 10, 2: 11, 3: 12, 4: 13][tmuxWindowId] ?? 10
                lines = ["%\(paneId) 0 0 80 24 0 off :0 \"host\""]
            } else {
                lines = []
            }
            session.connection.handleMessageForTesting(.commandResult(
                commandNumber: commandNumber,
                lines: lines,
                isError: false
            ))
            commandNumber += 1
        }

        let firstPaneRemoteOrder = destination.bonsplitController.tabs(inPane: targetPane)
            .compactMap { destination.panelIdFromSurfaceId($0.id) }
            .filter { $0 == one || $0 == two }
        let secondPaneRemoteOrder = destination.bonsplitController.tabs(inPane: secondPane)
            .compactMap { destination.panelIdFromSurfaceId($0.id) }
            .filter { $0 == three }
        #expect(firstPaneRemoteOrder == [two, one])
        #expect(secondPaneRemoteOrder == [three])
    }

    @Test
    func directTerminalCloseEntryPointsKillTransferredTmuxWindows() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let previousAppDelegate = AppDelegate.shared
            let previousActiveManager = TerminalController.shared.activeTabManagerForCallerNotification()
            let app = AppDelegate()
            let windowId = UUID()
            let manager = TabManager()
            app.registerMainWindowContextForTesting(windowId: windowId, tabManager: manager)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(windowId.uuidString)")
            app.registerMainWindow(
                window,
                windowId: windowId,
                tabManager: manager,
                sidebarState: SidebarState(),
                sidebarSelectionState: SidebarSelectionState()
            )
            defer {
                manager.window = nil
                window.orderOut(nil)
                window.close()
            }
            defer {
                app.unregisterMainWindowContextForTesting(windowId: windowId)
                manager.tabs.forEach { $0.teardownAllPanels() }
                AppDelegate.shared = previousAppDelegate
                TerminalController.shared.setActiveTabManager(previousActiveManager)
            }

            let session = try attachRemoteSession(
                app: app,
                manager: manager,
                destination: "user@direct-close",
                sessionName: "direct-close",
                windows: [
                    (windowId: 1, paneId: 10, name: "one"),
                    (windowId: 2, paneId: 11, name: "two"),
                    (windowId: 3, paneId: 12, name: "three"),
                    (windowId: 4, paneId: 13, name: "root"),
                ]
            )
            defer { session.tearDown(app: app) }

            let destination = manager.addWorkspace(title: "destination", select: false)
            let targetPane = try #require(destination.bonsplitController.allPaneIds.first)
            let one = try #require(session.mirror.panelIdByWindow[1])
            let two = try #require(session.mirror.panelIdByWindow[2])
            let three = try #require(session.mirror.panelIdByWindow[3])
            for panelId in [one, two, three] {
                #expect(app.moveSurface(
                    panelId: panelId,
                    toWorkspace: destination.id,
                    targetPane: targetPane,
                    focus: false,
                    focusWindow: false
                ))
            }

            manager.closeRuntimeSurface(tabId: destination.id, surfaceId: one)
            manager.confirmCloseHandler = { _, _, _ in true }
            manager.closeRuntimeSurfaceWithConfirmation(tabId: destination.id, surfaceId: two)
            manager.confirmCloseHandler = nil
            let scriptCommand = NSScriptCommand()
            _ = ScriptTerminal(workspaceId: destination.id, terminalId: three)
                .handleClose(scriptCommand)

            #expect(destination.panels[one] != nil)
            #expect(destination.panels[two] != nil)
            #expect(destination.panels[three] != nil)
            #expect(session.mirror.workspaceIdOwningWindow(1) == destination.id)
            #expect(session.mirror.workspaceIdOwningWindow(2) == destination.id)
            #expect(session.mirror.workspaceIdOwningWindow(3) == destination.id)

            session.writer.close()
            let commands = try String(
                decoding: session.pipe.fileHandleForReading.readToEnd() ?? Data(),
                as: UTF8.self
            )
            let killCommands = commands.split(separator: "\n")
                .filter { $0.hasPrefix("kill-window ") }
                .map(String.init)
            #expect(killCommands == [
                "kill-window -t @1",
                "kill-window -t @2",
                "kill-window -t @3",
            ])
        }
    }

    private struct AttachedRemoteSessionFixture {
        let host: RemoteTmuxHost
        let sessionName: String
        let connection: RemoteTmuxControlConnection
        let writer: RemoteTmuxControlPipeWriter
        let pipe: Pipe
        let workspace: Workspace
        let mirror: RemoteTmuxSessionMirror

        @MainActor
        func tearDown(app: AppDelegate) {
            app.remoteTmuxController.detach(host: host, sessionName: sessionName)
            writer.close()
            try? pipe.fileHandleForReading.close()
        }
    }

    private func attachRemoteSession(
        app: AppDelegate,
        manager: TabManager,
        destination: String,
        sessionName: String,
        windows: [(windowId: Int, paneId: Int, name: String)]
    ) throws -> AttachedRemoteSessionFixture {
        let host = RemoteTmuxHost(destination: destination)
        let connection = RemoteTmuxControlConnection(host: host, sessionName: sessionName)
        let pipe = Pipe()
        let writer = RemoteTmuxControlPipeWriter(
            handle: pipe.fileHandleForWriting,
            label: "remote-tmux-\(sessionName)-test",
            maxPendingBytes: 1 << 16,
            onFailure: {}
        )
        connection.installStdinWriterForTesting(writer)
        connection.handleMessageForTesting(.enter)
        connection.handleMessageForTesting(
            .commandResult(commandNumber: 0, lines: [], isError: false)
        )
        app.remoteTmuxController.cacheConnection(connection)
        #expect(try app.remoteTmuxController.mirrorSession(
            host: host,
            sessionName: sessionName,
            into: manager
        ))
        let mirror = try #require(
            app.remoteTmuxController.sessionMirror(host: host, sessionName: sessionName)
        )
        let workspaceId = try #require(mirror.mirroredWorkspaceId)
        let workspace = try #require(manager.tabs.first { $0.id == workspaceId })

        connection.handleMessageForTesting(.commandResult(
            commandNumber: 1,
            lines: windows.map { window in
                "@\(window.windowId) f92f,80x24,0,0,\(window.paneId) " +
                    "f92f,80x24,0,0,\(window.paneId) [] \(window.name)"
            },
            isError: false
        ))
        var commandNumber = 2
        while let kind = connection.pendingCommandKindsForTesting.first {
            let lines: [String]
            if case let .paneRects(tmuxWindowId, _) = kind,
               let index = windows.firstIndex(where: { $0.windowId == tmuxWindowId })
            {
                let window = windows[index]
                lines = [
                    "%\(window.paneId) 0 0 80 24 \(index == 0 ? 1 : 0) off :\(index) \"host\"",
                ]
            } else {
                lines = []
            }
            connection.handleMessageForTesting(
                .commandResult(commandNumber: commandNumber, lines: lines, isError: false)
            )
            commandNumber += 1
        }

        return AttachedRemoteSessionFixture(
            host: host,
            sessionName: sessionName,
            connection: connection,
            writer: writer,
            pipe: pipe,
            workspace: workspace,
            mirror: mirror
        )
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private final class ManualCoalescerScheduler {
        private struct PendingFlush {
            var isCancelled = false
            let action: @MainActor () -> Void
        }

        private var pendingFlushes: [PendingFlush] = []
        private(set) var delays: [TimeInterval] = []

        @MainActor
        func schedule(
            delay: TimeInterval,
            action: @escaping @MainActor () -> Void
        ) -> NotificationBurstCoalescer.Cancellation {
            let index = pendingFlushes.count
            delays.append(delay)
            pendingFlushes.append(PendingFlush(action: action))
            return { [weak self] in
                self?.pendingFlushes[index].isCancelled = true
            }
        }

        @MainActor
        func fire(at index: Int) {
            guard pendingFlushes.indices.contains(index), !pendingFlushes[index].isCancelled else { return }
            pendingFlushes[index].action()
        }
    }
}
