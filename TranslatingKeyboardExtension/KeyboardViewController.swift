import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>!
    private var model: KeyboardModel!

    override func viewDidLoad() {
        super.viewDidLoad()

        // The proxy is `Self.textDocumentProxy`. It and `advanceToNextInputMode`
        // are both members of `UIInputViewController`, so the model only
        // depends on the protocol surface.
        let services = ExtensionServices.shared
        let m = KeyboardModel(proxy: textDocumentProxy, expander: services.expander)
        m.advanceToNextInputMode = { [weak self] in
            self?.advanceToNextInputMode()
        }
        self.model = m

        let root = KeyboardRootView(model: m)
        hostingController = UIHostingController(rootView: root)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.didMove(toParent: self)
    }
}
