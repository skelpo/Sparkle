//
//  SUTouchBarButtonGroup.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Cocoa

internal final class SUTouchBarButtonGroup: NSViewController {

    internal var buttons: [NSButton]
    
    required init(referencingButtons: [NSButton]) {
        self.buttons = []
        super.init(nibName: nil, bundle: nil)

        let buttonGroup = NSView(frame: .zero)
        self.view = buttonGroup
        
        var constraints: [NSLayoutConstraint] = []
        var buttonCopies: [NSButton] = []
        
        for button in referencingButtons {
            let buttonCopy = NSButton(title: button.title, target: button.target, action: button.action)
            buttonCopy.tag = button.tag
            buttonCopy.isEnabled = button.isEnabled
            // Must be set explicitly, because NSWindow clears it
            // https://github.com/sparkle-project/Sparkle/pull/987#issuecomment-271539319
            if ObjectIdentifier(button) == ObjectIdentifier(referencingButtons.first!) {
                buttonCopy.keyEquivalent = "\r"
            }
            buttonCopy.translatesAutoresizingMaskIntoConstraints = false
            buttonCopies.append(buttonCopy)
            buttonGroup.addSubview(buttonCopy)
            
            // Custom layout is used for equal width buttons, to look more keyboard-like and mimic standard alerts
            // https://github.com/sparkle-project/Sparkle/pull/987#issuecomment-272324726
            constraints.append(.init(item: buttonCopy, attribute: .top, relatedBy: .equal, toItem: buttonGroup, attribute: .top, multiplier: 1.0, constant: 0.0))
            constraints.append(.init(item: buttonCopy, attribute: .bottom, relatedBy: .equal, toItem: buttonGroup, attribute: .bottom, multiplier: 1.0, constant: 0.0))
            if ObjectIdentifier(button) == ObjectIdentifier(referencingButtons.first!) {
                constraints.append(.init(item: buttonCopy, attribute: .trailing, relatedBy: .equal, toItem: buttonGroup, attribute: .trailing, multiplier: 1.0, constant: 0.0))
            } else {
                constraints.append(.init(item: buttonCopy, attribute: .trailing, relatedBy: .equal, toItem: buttonCopies.suffix(2).first!, attribute: .leading, multiplier: 1.0, constant: buttonCopies.count == 2 ? -8.0 : -32.0))
                constraints.append(.init(item: buttonCopy, attribute: .width, relatedBy: .equal, toItem: buttonCopies.suffix(2).first!, attribute: .width, multiplier: 1.0, constant: 0.0))
                constraints.last!.priority = .init(rawValue: 250)
            }
            if buttonCopies.count == referencingButtons.count {
                constraints.append(.init(item: buttonCopy, attribute: .leading, relatedBy: .equal, toItem: buttonGroup, attribute: .leading, multiplier: 1.0, constant: 0.0))
            }
        }
        NSLayoutConstraint.activate(constraints)
        self.buttons = buttonCopies
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
