import UIKit
import UniformTypeIdentifiers

final class GameViewController: UIViewController {
    private let glView = GameGLView(frame: .zero)
    private let discStore = DiscStore()
    private let audio = AudioEngine()
    private let controllers = ControllerManager()

    private var disc1: DiscInfo?
    private var disc2: DiscInfo?
    private var activeSlot: Int?
    private var isBusy = false

    private let disc1Label = UILabel()
    private let disc2Label = UILabel()
    private let startButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureGL()
        configureOverlay()
        loadExistingDiscs()
        controllers.onChange = { [weak self] _ in
            self?.updateStatus()
        }
        refreshUI()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            glView.stopRendering()
            audio.stop()
            re4_core_stop()
        }
    }

    // MARK: - OpenGL

    private func configureGL() {
        glView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glView)
        NSLayoutConstraint.activate([
            glView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glView.topAnchor.constraint(equalTo: view.topAnchor),
            glView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        glView.onFrame = { [weak self] delta in
            guard let self = self else { return }
            var pad = self.controllers.padState()
            re4_core_set_pad(&pad)
            re4_core_frame(delta)
        }
        glView.startRendering()
    }

    // MARK: - Overlay

    private func configureOverlay() {
        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = 18
        panel.layer.masksToBounds = true
        view.addSubview(panel)

        let title = UILabel()
        title.text = "CubeEvil4"
        title.font = .systemFont(ofSize: 26, weight: .heavy)
        title.textColor = .white

        let subtitle = UILabel()
        subtitle.text = "Resident Evil 4 (GameCube) - base iOS"
        subtitle.font = .systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.62)
        subtitle.numberOfLines = 1

        configureDiscLabel(disc1Label)
        configureDiscLabel(disc2Label)

        let disc1Row = makeDiscRow(slot: 1, title: "Importar Disco 1", label: disc1Label)
        let disc2Row = makeDiscRow(slot: 2, title: "Importar Disco 2", label: disc2Label)

        startButton.setTitle("Iniciar jogo", for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        startButton.setTitleColor(.white, for: .normal)
        startButton.backgroundColor = UIColor(red: 0.70, green: 0.11, blue: 0.11, alpha: 1.0)
        startButton.layer.cornerRadius = 10
        startButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        spinner.color = .white
        spinner.hidesWhenStopped = true

        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        statusLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            title,
            subtitle,
            disc1Row,
            disc2Row,
            startButton,
            spinner,
            statusLabel
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(12, after: subtitle)
        stack.setCustomSpacing(12, after: disc2Row)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)

        let panelWidth = panel.widthAnchor.constraint(equalToConstant: 360)
        panelWidth.priority = .defaultHigh

        let panelBottom = panel.bottomAnchor.constraint(
            lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -18
        )
        panelBottom.priority = .init(999)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 18
            ),
            panel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 18
            ),
            panelWidth,
            panel.widthAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor,
                constant: -36
            ),
            panelBottom,

            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -18)
        ])
    }

    private func configureDiscLabel(_ label: UILabel) {
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 2
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func makeDiscRow(slot: Int, title: String, label: UILabel) -> UIStackView {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        button.tag = slot
        button.addTarget(self, action: #selector(importTapped(_:)), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [label, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
    }

    // MARK: - Discs

    private func loadExistingDiscs() {
        disc1 = discStore.existingDisc(slot: 1)
        disc2 = discStore.existingDisc(slot: 2)
    }

    @objc private func importTapped(_ sender: UIButton) {
        guard !isBusy else { return }
        activeSlot = sender.tag
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func importDisc(slot: Int, from url: URL) {
        setBusy(true)
        statusLabel.text = "Importando disco \(slot)... isso pode levar alguns minutos."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let info = try self.discStore.importDisc(slot: slot, from: url)
                DispatchQueue.main.async {
                    if slot == 1 {
                        self.disc1 = info
                    } else {
                        self.disc2 = info
                    }
                    self.setBusy(false)
                    self.refreshUI()
                }
            } catch {
                DispatchQueue.main.async {
                    self.setBusy(false)
                    self.refreshUI()
                    self.alert(title: "Falha ao importar", message: error.localizedDescription)
                }
            }
        }
    }

    private func discText(_ info: DiscInfo?, slot: Int) -> String {
        guard let info = info else {
            return "Disco \(slot): nao importado"
        }
        return "Disco \(slot): \(info.gameID)\n\(info.format) - \(info.sizeText)"
    }

    // MARK: - Start

    @objc private func startTapped() {
        guard let first = disc1, let second = disc2 else { return }

        setBusy(true)
        let result = re4_core_start(first.url.path, second.url.path, discStore.dataDirectory.path)
        setBusy(false)

        if result == RE4_OK && re4_core_is_available() {
            audio.start()
            refreshUI()
            return
        }

        var detail = "Erro desconhecido."
        if let message = re4_core_last_error() {
            detail = String(cString: message)
        }
        alert(title: "Nucleo ainda nao integrado", message: detail)
    }

    // MARK: - UI state

    private func refreshUI() {
        disc1Label.text = discText(disc1, slot: 1)
        disc2Label.text = discText(disc2, slot: 2)

        let ready = disc1 != nil && disc2 != nil && !isBusy
        startButton.isEnabled = ready
        startButton.alpha = ready ? 1.0 : 0.45
        updateStatus()
    }

    private func updateStatus() {
        let coreName: String
        if let version = re4_core_version() {
            coreName = String(cString: version)
        } else {
            coreName = "?"
        }
        statusLabel.text = "\(glView.rendererInfo)\nControle: \(controllers.displayName)\n\(coreName)"
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        if busy {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        refreshUI()
    }

    private func alert(title: String, message: String) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .default))
        present(controller, animated: true)
    }
}

extension GameViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let slot = activeSlot, let url = urls.first else {
            activeSlot = nil
            return
        }
        activeSlot = nil
        importDisc(slot: slot, from: url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        activeSlot = nil
    }
}
