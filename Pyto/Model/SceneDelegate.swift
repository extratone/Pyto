//
//  SceneDelagate.swift
//  Pyto
//
//  Created by Emma Labbé on 08-06-19.
//  Copyright © 2018-2021 Emma Labbé. All rights reserved.
//

import UIKit
import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import Dynamic

/// The scene delegate.
@objc class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    /// The document browser associated with this scene.
    var documentBrowserViewController: DocumentBrowserViewController? {
        return window?.rootViewController as? DocumentBrowserViewController
    }
    
    /// Shows onboarding if needed.
    func showOnboarding() {
        checkIfUnlocked(on: window)
    }
    
    /// The scene state.
    var sceneStateStore = SceneStateStore()
    
    /// Opens a document after the scene is shown.
    ///
    /// - Parameters:
    ///     - url: The URL to open.
    ///     - run: A boolean indicating whether the script should be executed.
    ///     - isShortcut: A boolean indicating whether the script is executed from Shortcuts.
    func openDocument(at url: URL, run: Bool, folder: URL?, isShortcut: Bool) {
        
        if #available(iOS 14.0, *), isiOSAppOnMac && documentBrowserViewController == nil {
            window?.rootViewController = DocumentBrowserViewController(forOpening: [.pythonScript/*, .init(exportedAs: "ch.ada.pytoui")*/])
        }
        
        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { [weak self] (timer) in
            guard let self = self else {
                return
            }
            
            if let doc = self.documentBrowserViewController {
                if run || isiOSAppOnMac {
                    doc.openDocument(url, run: run, isShortcut: isShortcut, folder: folder)
                } else {
                    doc.revealDocument(at: url, importIfNeeded: false) { (url_, _) in
                        doc.openDocument(url_ ?? url, run: run, isShortcut: isShortcut, folder: folder)
                    }
                }
                timer.invalidate()
            }
        })
    }
    
    // MARK: - Scene delegate
    
    var window: UIWindow?
    
    @available(iOS 13.0, *)
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        
        #if VPP || SCREENSHOTS || DEBUG
        changingUserDefaultsInAppPurchasesValues = true
        isPurchased.boolValue = true
        changingUserDefaultsInAppPurchasesValues = true
        isLiteVersion.boolValue = false
        isUnlocked = true
        isReceiptChecked = true
        #else
        verifyReceipt()
        #endif
        
        window?.tintColor = ConsoleViewController.choosenTheme.tintColor
        
        if let vc = SceneDelegate.viewControllerToShow {
            SceneDelegate.viewControllerToShow = nil
            
            let blankVC = ViewController()
            blankVC.sceneSession = session
            blankVC.viewControllerToPresent = vc
            blankVC.completion = SceneDelegate.viewControllerDidShow
            window?.rootViewController = blankVC
            
            return
        }
        
        if #available(iOS 14.0, *), isiOSAppOnMac {
            window?.rootViewController = DocumentBrowserViewController(forOpening: [.pythonScript/*, .init(exportedAs: "ch.ada.pytoui")*/])
        }
        
        window?.overrideUserInterfaceStyle = ConsoleViewController.choosenTheme.userInterfaceStyle
        if let window = self.window {
            SceneDelegate.windows.append(window)
        }
        
        if connectionOptions.urlContexts.count > 0 {
            self.scene(scene, openURLContexts: connectionOptions.urlContexts)
            return
        }
        
        if connectionOptions.userActivities.count > 0 {
            self.scene(scene, continue: connectionOptions.userActivities.first!)
            return
        }
        
        if let item = connectionOptions.shortcutItem, let windowScene = scene as? UIWindowScene {
            self.windowScene(windowScene, performActionFor: item, completionHandler: { _ in })
            return
        }
        
        if let restorationActivity = session.stateRestorationActivity, #available(iOS 14.0, *) {
            restoreActivity(restorationActivity, session: session)
        }
    }
    
    @available(iOS 13.0, *)
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        
        func open() {
            if shortcutItem.type == "PyPI" {
                let vc = MenuTableViewController.makePyPiView()
                let navVC = UINavigationController(rootViewController: vc)
                navVC.modalPresentationStyle = .formSheet
                navVC.navigationBar.prefersLargeTitles = true
                windowScene.windows.first?.topViewController?.present(navVC, animated: true, completion: nil)
                completionHandler(true)
            } else if shortcutItem.type == "REPL" {
                windowScene.windows.first?.topViewController?.present(UIStoryboard(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "repl"), animated: true, completion: nil)
                completionHandler(true)
            } else {
                completionHandler(false)
            }
        }
        
        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { [weak self] (timer) in
            
            var otherCondition = true
            if shortcutItem.type == "REPL" {
                otherCondition = Python.shared.isSetup
            }
            
            if self?.documentBrowserViewController != nil && otherCondition {
                
                open()
                
                timer.invalidate()
            }
        })
    }
    
    @available(iOS 13.0, *)
    func sceneWillResignActive(_ scene: UIScene) {
        #if MAIN
        (UIApplication.shared.delegate as? AppDelegate)?.copyModules()
        
        if #available(iOS 14.0, *), let windowScene = scene as? UIWindowScene {
            (EditorView.EditorStore.perScene[windowScene]?.editor?.viewController as? EditorSplitViewController)?.editor?.save()
        } else {
            ((window?.rootViewController?.presentedViewController as? UINavigationController)?.viewControllers.first as? EditorSplitViewController)?.editor?.save()
        }
        #endif
    }
    
    @available(iOS 13.0, *)
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        continueActivity(userActivity)
    }
    
    @available(iOS 13.0, *)
    func sceneDidDisconnect(_ scene: UIScene) {
        ((window?.rootViewController?.presentedViewController as? UINavigationController)?.viewControllers.first as? EditorSplitViewController)?.editor?.save()
    }
    
    @available(iOS 13.0, *)
    func sceneDidEnterBackground(_ scene: UIScene) {
        ((window?.rootViewController?.presentedViewController as? UINavigationController)?.viewControllers.first as? EditorSplitViewController)?.editor?.save()
    }
    
    @available(iOS 13.0, *)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        
        guard let inputURL = URLContexts.first?.url else {
            return
        }
        
        if inputURL.scheme == "pyto" {
            if inputURL.host == "upgrade" { // Upgrade
                if isLiteVersion.boolValue, isPurchased.boolValue {
                    purchase(id: .upgrade, window: window)
                }
            } else if inputURL.host == "inspector" { // The inspector
                guard let query = inputURL.query?.removingPercentEncoding, let data = query.data(using: .utf8) else {
                    return
                }
                                
                do {
                    let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    
                    let vc = (scene as? UIWindowScene)?.windows.first?.topViewController
                    let controller = UIHostingController(rootView: JSONBrowserNavigationView(items: dict ?? [:], dismiss: {
                        vc?.dismiss(animated: true, completion: nil)
                    }))
                    vc?.present(controller, animated: true, completion: nil)
                } catch {
                    NSLog("%@", error.localizedDescription)
                }
            } else if inputURL.host == "callback" { // I don't remember what that does hahhahah; Edit: Bruh it sets the URL received from an app using x-callback URLs.
                PyCallbackHelper.url = inputURL.absoluteString
            } else if inputURL.host == "x-callback" { // x-callback
                PyCallbackHelper.cancelURL = inputURL.queryParameters?["x-cancel"]
                PyCallbackHelper.errorURL = inputURL.queryParameters?["x-error"]
                PyCallbackHelper.successURL = inputURL.queryParameters?["x-success"]
            
                
                guard let documentBrowserViewController = documentBrowserViewController else {
                    window?.rootViewController?.dismiss(animated: true, completion: {
                        self.scene(scene, openURLContexts: URLContexts)
                    })
                    return
                }
                
                if let code = inputURL.queryParameters?["code"] {
                    PyCallbackHelper.code = code
                    documentBrowserViewController.run(code: code)
                }
            } else if inputURL.host == "widget" || inputURL.host == "automator" { // Open script from widget or Automator
                guard let bookmarkString = inputURL.queryParameters?["bookmark"] else {
                    return
                }
                if let bookmarkData = Data(base64Encoded: bookmarkString) {
                    do {
                        var isStale = false
                        let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
                        _ = url.startAccessingSecurityScopedResource()
                        Python.shared.widgetLink = inputURL.queryParameters?["link"]
                        _ = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false, block: { [weak self] (_) in
                            // I THINK waiting reduces the risk of a weird exception
                            if inputURL.host == "automator" {
                                
                                let arguments = (inputURL.queryParameters?["arguments"] ?? "")
                                
                                var args: [String]
                                
                                do {
                                    
                                    if let argsData = Data(base64Encoded: arguments) {
                                    
                                        let json = try JSONDecoder().decode([String].self, from: argsData)
                                    
                                        args = json
                                    } else {
                                        args = arguments.components(separatedBy: " ")
                                        ParseArgs(&args)
                                    }
                                } catch {
                                    args = arguments.components(separatedBy: " ")
                                    ParseArgs(&args)
                                }
                                
                                RunShortcutsScript(at: url, arguments: args, sendOutput: false)
                            } else {
                                self?.openDocument(at: url, run: true, folder: nil, isShortcut: false)
                            }
                        })
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
            
            return
        }
        
        // Open script
        
        // Ensure the URL is a file URL
        guard inputURL.isFileURL else {
            
            guard let query = inputURL.query?.removingPercentEncoding else {
                return
            }
            
            // Run code passed to the URL
            documentBrowserViewController?.run(code: query)
            
            return
        }
        
        _ = inputURL.startAccessingSecurityScopedResource()
        
        // Reveal / import the document at the URL
        
        openDocument(at: inputURL, run: false, folder: nil, isShortcut: false)
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        if isiOSAppOnMac { // Close document browser window because we only need the panel. I can't find a pattern in this bug so I can't really file a radar :(
            DispatchQueue.main.asyncAfter(deadline: .now()+0.5) { [weak self] in
                if self?.window?.rootViewController is DocumentBrowserViewController, self?.window?.rootViewController?.presentedViewController == nil {
                    var window = Dynamic.NSApplication.sharedApplication.delegate.hostWindowForUIWindow(self?.window)
                    
                    if window.attachedWindow.asObject != nil && !(window.attachedWindow.asObject is Error) {
                        window = window.attachedWindow
                    }
                    
                    window.close()
                }
            }
        }
    }
}

