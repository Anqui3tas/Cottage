//
//  MessagesViewController.swift
//  cottage.message MessagesExtension
//
//  Created by Quentin Brooks on 1/10/26.
//

import Messages
import SwiftUI
import UIKit

final class MessagesViewController: MSMessagesAppViewController {
    private let state = CottageMessagesState()

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        state.isExpanded = presentationStyle == .expanded
        // Reload shared packs each time Messages opens the extension.
        state.reloadID = UUID()
    }

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        state.isExpanded = presentationStyle == .expanded
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: CottageMessagesPicker(state: state))
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}
