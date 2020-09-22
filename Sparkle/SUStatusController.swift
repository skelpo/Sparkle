//
//  SUStatusController.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Cocoa

@objc internal final class SUStatusController: NSWindowController, NSTouchBarDelegate {

    // MARK: - Outlets

    @IBOutlet internal var actionButton: NSButton!
    @IBOutlet internal var progressBar: NSProgressIndicator!
    @IBOutlet internal var statusTextField: NSTextField!

    // MARK: - API properties
    
    internal var statusText: String?
    internal var progressValue: Double = 0.0
    internal var maxProgressValue: Double = 0.0 {
        didSet {
            maxProgressValue = Swift.max(maxProgressValue, 0.0)
            self.progressValue = 0.0
            self.progressBar.isIndeterminate = (maxProgressValue == 0.0)
            self.progressBar.startAnimation(self)
            self.progressBar.usesThreadedAnimation = true
        }
    }
    internal var isButtonEnabled: Bool {
        get { self.actionButton.isEnabled }
        set { self.actionButton.isEnabled = newValue }
    }
    
    // MARK: - Private properties
    
    private var title: String = ""
    private var buttonTitle: String = ""
    private let host: SUHost
    private var touchBarButton: NSButton?
    
    // MARK: - Initializers
    
    @objc(initWithHost:)
    internal required init(host: SUHost) {
        self.host = host
        super.init(window: nil)
        self.shouldCascadeWindows = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    public override var windowNibName: NSNib.Name? { "SUStatus" }
    
    // MARK: - Lifecycle
    
    public override func windowDidLoad() {
        if SUApplicationInfo.isBackground(application: NSApp) {
            self.window!.level = .floating
        }
        self.window!.center()
        self.window!.setFrameAutosaveName("SUStatusFrame")
        self.progressBar.usesThreadedAnimation = true
        self.statusTextField.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular)
    }
    
    // MARK: - Bindings
    
    internal var windowTitle: String { String.localizedStringWithFormat(SULocalizedString("Updating %@", nil), self.host.name) }
    
    internal var applicationIcon: NSImage? { SUApplicationInfo.bestIcon(forHost: self.host) }
    
    internal var progressBarShouldAnimate: Bool { true }
    
    // MARK: - API methods
    
    @objc(beginActionWithTitle:maxProgressValue:statusText:)
    internal func beginAction(title: String, maxProgressValue: Double, statusText: String?) {
        self.title = title
        self.maxProgressValue = maxProgressValue
        self.statusText = statusText
    }
    
    @objc(setButtonTitle:target:action:isDefault:)
    internal func set(buttonTitle: String, target: AnyObject?, action: Selector?, isDefault: Bool) {
        self.buttonTitle = buttonTitle
        self.actionButton.sizeToFit()
        // Except we're going to add 15px for padding and move it over so that it's always 15px from the side of the window.
        self.actionButton.frame = .init(
            x: self.window!.frame.size.width - 15.0 - (self.actionButton.frame.size.width + 15.0),
            y: self.actionButton.frame.origin.y,
            width: self.actionButton.frame.size.width + 15.0,
            height: self.actionButton.frame.size.height
        )
        self.actionButton.superview?.display() // Redisplay superview to clean up artifacts
        self.actionButton.target = target
        self.actionButton.action = action
        self.actionButton.keyEquivalent = isDefault ? "\r" : ""
        self.touchBarButton?.target = self.actionButton.target
        self.touchBarButton?.action = self.actionButton.action
        self.touchBarButton?.keyEquivalent = self.actionButton.keyEquivalent
        self.isButtonEnabled = (target != nil)
    }
    
    private static var TouchBarIndentifier: NSTouchBarItem.Identifier { .init("\(SUBundleIdentifier).SUStatusController") }

    internal override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.defaultItemIdentifiers = [Self.TouchBarIndentifier]
        touchBar.principalItemIdentifier = Self.TouchBarIndentifier
        touchBar.delegate = self
        return touchBar
    }
    
    internal func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
            case Self.TouchBarIndentifier:
                let item = NSCustomTouchBarItem(identifier: identifier)
                let group = SUTouchBarButtonGroup(referencingButtons:[self.actionButton])
                item.viewController = group
                self.touchBarButton = group.buttons.first!
                self.touchBarButton?.bind(.init("title"), to: self.actionButton!, withKeyPath: "title", options: nil)
                self.touchBarButton?.bind(.init("enabled"), to: self.actionButton!, withKeyPath: "enabled", options: nil)
                return item
            default:
                return nil
        }
    }
}
/*
static NSString *const SUStatusControllerTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUStatusController";

@interface SUStatusController () <NSTouchBarDelegate>
@property (copy) NSString *title, *buttonTitle;
@property (strong) SUHost *host;
@property NSButton *touchBarButton;
@end

@implementation SUStatusController

- (BOOL)progressBarShouldAnimate
{
    return YES;
}

- (void)setButtonEnabled:(BOOL)enabled
{
    [self.actionButton setEnabled:enabled];
}

- (BOOL)isButtonEnabled
{
    return [self.actionButton isEnabled];
}

- (void)setMaxProgressValue:(double)value
{
	if (value < 0.0) value = 0.0;
    maxProgressValue = value;
    [self setProgressValue:0.0];
    [self.progressBar setIndeterminate:(value == 0.0)];
    [self.progressBar startAnimation:self];
    [self.progressBar setUsesThreadedAnimation:YES];
}


- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [(NSTouchBar *)[NSClassFromString(@"NSTouchBar") alloc] init];
    touchBar.defaultItemIdentifiers = @[ SUStatusControllerTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUStatusControllerTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier API_AVAILABLE(macos(10.12.2))
{
    if ([identifier isEqualToString:SUStatusControllerTouchBarIndentifier]) {
        NSCustomTouchBarItem *item = [(NSCustomTouchBarItem *)[NSClassFromString(@"NSCustomTouchBarItem") alloc] initWithIdentifier:identifier];
        SUTouchBarButtonGroup *group = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[self.actionButton,]];
        item.viewController = group;
        self.touchBarButton = group.buttons.firstObject;
        [self.touchBarButton bind:@"title" toObject:self.actionButton withKeyPath:@"title" options:nil];
        [self.touchBarButton bind:@"enabled" toObject:self.actionButton withKeyPath:@"enabled" options:nil];
        return item;
    }
    return nil;
}
*/
