import SwiftUI

/// Where the marker is chosen. The API key is typed here, saved to the Keychain and never
/// shown again; the rest of the card explains exactly what leaves the Mac when OpenRouter is
/// in use, because a paper being marked in the cloud is the user's decision to make.
struct MarkingSettingsCard: View {
    @Binding var isExpanded: Bool
    /// Shared with the marking screen's own marker menu, so the two controls can never
    /// disagree about which marker is in use.
    @Binding var preference: MarkingBackendPreference

    @State private var apiKey = ""
    @State private var hasKey = MarkingKeychain.hasKey
    @State private var model = MarkingPreferences.model
    @State private var models: [OpenRouterModel] = []
    @State private var isLoadingModels = false
    @State private var isTesting = false
    @State private var message: String?
    @State private var messageIsError = false

    private var onDeviceAvailable: Bool { MarkingService.availability.isAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            LinearGradient(
                                colors: [Neon.accent, Neon.accentAlt],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Marking Settings")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(preference.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Pill(
                        text: statusText,
                        color: statusColor,
                        icon: statusIcon
                    )
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                preferenceRow
                keyRow
                modelRow
                privacyNote
                if let message {
                    Label(message, systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(messageIsError ? Color.orange : Color.studyGreen)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
        .task {
            if hasKey, models.isEmpty { await loadModels() }
        }
    }

    private var statusText: String {
        switch preference {
        case .automatic:
            if onDeviceAvailable { return hasKey ? "ON-DEVICE + FALLBACK" : "ON THIS MAC" }
            return hasKey ? "OPENROUTER" : "NOT READY"
        case .onDevice:
            return onDeviceAvailable ? "ON THIS MAC" : "NOT READY"
        case .openRouter:
            return hasKey ? "OPENROUTER" : "KEY NEEDED"
        }
    }

    private var statusColor: Color {
        MarkingService.isReady ? .studyGreen : .studyAmber
    }

    private var statusIcon: String {
        MarkingService.isReady ? "checkmark.seal" : "exclamationmark.circle"
    }

    // MARK: - Rows

    private var preferenceRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MARKER")
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            Picker("Marker", selection: $preference) {
                ForEach(MarkingBackendPreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: preference) { _, newValue in
                MarkingPreferences.preference = newValue
                message = nil
                if newValue != .onDevice, hasKey, models.isEmpty {
                    Task { await loadModels() }
                }
            }
            .onChange(of: hasKey) { _, newValue in
                if !newValue, models.isEmpty { message = nil }
            }
            Text(preference.summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("OPENROUTER API KEY")
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(hasKey ? "A key is stored in the Keychain" : "sk-or-v1-…", text: $apiKey)
                    .bentoField()
                Button(hasKey ? "Replace" : "Save Key") { saveKey() }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.primary)
                    .font(.system(size: 10, weight: .semibold))
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasKey {
                    Button("Remove") { removeKey() }
                        .buttonStyle(.bentoBordered)
                        .bentoTint(.danger)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            Text(hasKey
                 ? "Kept in your login Keychain. Never written to the career file, the repository or a log."
                 : "Create one at openrouter.ai → Keys. Nothing is sent anywhere until you add a key and choose OpenRouter.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MODEL")
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                BentoMenu(
                    selection: $model,
                    options: modelOptions,
                    placeholder: "Choose a model",
                    width: 300
                )
                .onChange(of: model) { _, newValue in
                    MarkingPreferences.model = newValue
                    message = nil
                }
                Button(isLoadingModels ? "Loading…" : "Refresh List") {
                    Task { await loadModels() }
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.white)
                .font(.system(size: 10, weight: .semibold))
                .disabled(isLoadingModels)
                Button(isTesting ? "Testing…" : "Test Key") {
                    Task { await testKey() }
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.secondary)
                .font(.system(size: 10, weight: .semibold))
                .disabled(isTesting || !hasKey || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            TextField("…or paste a model slug, e.g. google/gemini-2.5-flash", text: $model)
                .bentoField()
                .onSubmit { MarkingPreferences.model = model }
            Text("Only models that accept images are listed, because a handwritten paper has to be sent as a scan. The list is fetched from OpenRouter, so it follows whatever they host today. Test Key marks one trivial question so a broken key or model is caught before a real paper.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.studyAmber)
            Text("With OpenRouter selected, the paper's text and any scans are sent to a third-party service using your own account and paid for by your own credit. Apple Intelligence marks everything on this Mac and sends nothing.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Models

    /// The fetched list, with whatever slug is stored kept visible even if it is not in the
    /// current catalogue, so a saved choice never silently disappears.
    private var modelOptions: [BentoOption<String>] {
        var options = models.map { model in
            BentoOption(model.displayName, value: model.id, subtitle: model.id, symbol: "cloud")
        }
        if !model.isEmpty, !models.contains(where: { $0.id == model }) {
            options.insert(BentoOption(model, value: model, subtitle: "Saved slug", symbol: "pin"), at: 0)
        }
        if options.isEmpty {
            options = [BentoOption("Fetch the list to choose a model", value: "", symbol: "arrow.clockwise")]
        }
        return options
    }

    private func loadModels() async {
        isLoadingModels = true
        message = nil
        do {
            let fetched = try await OpenRouterClient.models()
            await MainActor.run {
                models = fetched
                isLoadingModels = false
                message = fetched.isEmpty
                    ? "OpenRouter returned no image-capable models. Paste a slug instead."
                    : "\(fetched.count) image-capable models loaded."
                messageIsError = fetched.isEmpty
            }
        } catch {
            await MainActor.run {
                isLoadingModels = false
                message = "Could not reach OpenRouter: \(error.localizedDescription) You can still paste a model slug by hand."
                messageIsError = true
            }
        }
    }

    // MARK: - Key

    /// Sends one one-mark question through the real client, which is the only honest way to
    /// know the key, the model slug and the parsing all line up.
    private func testKey() async {
        guard let key = MarkingKeychain.read(), !key.isEmpty else {
            messageIsError = true
            message = "Save a key before testing it."
            return
        }
        isTesting = true
        message = nil
        do {
            let verdict = try await OpenRouterClient.test(key: key, model: model)
            await MainActor.run {
                isTesting = false
                messageIsError = false
                message = verdict
            }
        } catch {
            await MainActor.run {
                isTesting = false
                messageIsError = true
                message = error.localizedDescription
            }
        }
    }

    private func saveKey() {
        guard MarkingKeychain.save(apiKey) else {
            hasKey = MarkingKeychain.hasKey
            messageIsError = true
            message = "The key was not saved. It looks empty — or the Keychain refused it."
            return
        }
        apiKey = ""
        hasKey = true
        messageIsError = false
        message = "Key saved to the Keychain."
        if models.isEmpty { Task { await loadModels() } }
    }

    private func removeKey() {
        MarkingKeychain.delete()
        apiKey = ""
        hasKey = false
        messageIsError = false
        message = "Key removed. Papers will be marked on this Mac only."
        if preference == .openRouter {
            preference = .automatic
        }
    }
}
