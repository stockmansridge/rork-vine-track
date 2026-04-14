import SwiftUI
import CoreLocation

struct HomeView: View {
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @Environment(AuthService.self) private var authService
    @State private var currentMode: PinMode = .repairs
    @State private var lastDroppedPin: VinePin?
    @State private var showPinConfirmation: Bool = false
    @State private var showCamera: Bool = false
    @State private var pendingPin: VinePin?
    @State private var showPhotoPromptAlert: Bool = false
    @State private var photoPromptTask: Task<Void, Never>?
    @State private var showGrowthStagePicker: Bool = false
    @State private var pendingGrowthStageConfig: ButtonConfig?
    @State private var pendingGrowthStageSide: PinSide = .left

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modeSelector
                    .padding(.horizontal)
                    .padding(.top, 8)

                TabView(selection: $currentMode) {
                    buttonGrid(for: .repairs)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .tag(PinMode.repairs)

                    buttonGrid(for: .growth)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .tag(PinMode.growth)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy(duration: 0.25), value: currentMode)

                if let pin = lastDroppedPin, showPinConfirmation {
                    pinConfirmationBanner(pin: pin)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        if let logoData = store.selectedVineyard?.logoData,
                           let uiImage = UIImage(data: logoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(.rect(cornerRadius: 6))
                        }
                        Text(store.selectedVineyard?.name ?? "VineTrack")
                            .font(.headline)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .sensoryFeedback(.success, trigger: lastDroppedPin?.id)
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker { data in
                    commitPendingPin(photoData: data)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showGrowthStagePicker) {
                GrowthStagePickerSheet { stage in
                    if let config = pendingGrowthStageConfig {
                        dropGrowthStagePin(config: config, side: pendingGrowthStageSide, stage: stage)
                    }
                }
            }
            .alert("Take a Photo?", isPresented: $showPhotoPromptAlert) {
                Button("Take Photo") {
                    photoPromptTask?.cancel()
                    showCamera = true
                }
                Button("No", role: .cancel) {
                    photoPromptTask?.cancel()
                    commitPendingPin(photoData: nil)
                }
            } message: {
                Text("Would you like to take a photo of this pin?")
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(PinMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        currentMode = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .repairs ? "wrench.fill" : "leaf.fill")
                            .font(.caption)
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                        .background(currentMode == mode ? Color.accentColor : Color.clear)
                        .foregroundStyle(currentMode == mode ? .white : .primary)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 10))
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 10))
    }

    private func buttonGrid(for mode: PinMode) -> some View {
        let buttons = store.buttonsForMode(mode)
        let leftButtons = Array(buttons.prefix(4))
        let rightButtons = Array(buttons.suffix(4))

        return HStack(spacing: 16) {
            buttonColumn(buttons: leftButtons, side: .left, label: "LEFT", mode: mode)
            buttonColumn(buttons: rightButtons, side: .right, label: "RIGHT", mode: mode)
        }
    }

    private func buttonColumn(buttons: [ButtonConfig], side: PinSide, label: String, mode: PinMode) -> some View {
        VStack(spacing: 12) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.5)

            ForEach(buttons) { config in
                PinButton(config: config, side: side) {
                    if mode == .growth && config.isGrowthStageButton {
                        handleGrowthStageButton(config: config, side: side)
                    } else {
                        dropPin(config: config, side: side, mode: mode)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func pinConfirmationBanner(pin: VinePin) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.fromString(pin.buttonColor))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pin Dropped")
                    .font(.subheadline.weight(.semibold))
                Text("\(pin.buttonName) \u{2022} \(pin.side.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(VineyardTheme.leafGreen)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private func handleGrowthStageButton(config: ButtonConfig, side: PinSide) {
        pendingGrowthStageConfig = config
        pendingGrowthStageSide = side
        showGrowthStagePicker = true
    }

    private func dropGrowthStagePin(config: ButtonConfig, side: PinSide, stage: GrowthStage) {
        let location = locationService.location
        let heading = locationService.heading
        let activeTrip = store.activeTrip

        let resolvedPaddockId: UUID?
        let resolvedRowNumber: Int?

        if let activeTrip {
            resolvedPaddockId = activeTrip.paddockId
            resolvedRowNumber = Int(activeTrip.currentRowNumber)
        } else if let coord = location?.coordinate {
            let lookup = findPaddockAndRow(coordinate: coord, paddocks: store.paddocks)
            resolvedPaddockId = lookup?.paddockId
            resolvedRowNumber = lookup?.closestRowNumber
        } else {
            resolvedPaddockId = nil
            resolvedRowNumber = nil
        }

        let pin = VinePin(
            latitude: location?.coordinate.latitude ?? 0,
            longitude: location?.coordinate.longitude ?? 0,
            heading: heading?.trueHeading ?? 0,
            buttonName: stage.shortName,
            buttonColor: config.color,
            side: side,
            mode: currentMode,
            paddockId: resolvedPaddockId,
            rowNumber: resolvedRowNumber,
            createdBy: authService.userName.isEmpty ? nil : authService.userName,
            growthStageCode: stage.code
        )

        if store.settings.autoPhotoPrompt {
            pendingPin = pin
            showPhotoPromptAlert = true
            photoPromptTask?.cancel()
            photoPromptTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                showPhotoPromptAlert = false
                commitPendingPin(photoData: nil)
            }
        } else {
            commitPin(pin)
        }
    }

    private func dropPin(config: ButtonConfig, side: PinSide, mode: PinMode? = nil) {
        let location = locationService.location
        let heading = locationService.heading
        let activeTrip = store.activeTrip

        let resolvedPaddockId: UUID?
        let resolvedRowNumber: Int?

        if let activeTrip {
            resolvedPaddockId = activeTrip.paddockId
            resolvedRowNumber = Int(activeTrip.currentRowNumber)
        } else if let coord = location?.coordinate {
            let lookup = findPaddockAndRow(coordinate: coord, paddocks: store.paddocks)
            resolvedPaddockId = lookup?.paddockId
            resolvedRowNumber = lookup?.closestRowNumber
        } else {
            resolvedPaddockId = nil
            resolvedRowNumber = nil
        }

        let pin = VinePin(
            latitude: location?.coordinate.latitude ?? 0,
            longitude: location?.coordinate.longitude ?? 0,
            heading: heading?.trueHeading ?? 0,
            buttonName: config.name,
            buttonColor: config.color,
            side: side,
            mode: mode ?? currentMode,
            paddockId: resolvedPaddockId,
            rowNumber: resolvedRowNumber,
            createdBy: authService.userName.isEmpty ? nil : authService.userName
        )

        if store.settings.autoPhotoPrompt {
            pendingPin = pin
            showPhotoPromptAlert = true
            photoPromptTask?.cancel()
            photoPromptTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                showPhotoPromptAlert = false
                commitPendingPin(photoData: nil)
            }
        } else {
            commitPin(pin)
        }
    }

    private func commitPendingPin(photoData: Data?) {
        guard var pin = pendingPin else { return }
        pin.photoData = photoData
        pendingPin = nil
        commitPin(pin)
    }

    private func commitPin(_ pin: VinePin) {
        store.addPin(pin)

        withAnimation(.snappy) {
            lastDroppedPin = pin
            showPinConfirmation = true
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                showPinConfirmation = false
            }
        }
    }
}

struct PinButton: View {
    let config: ButtonConfig
    let side: PinSide
    let action: () -> Void

    private var buttonColor: Color {
        Color.fromString(config.color)
    }

    private var isLightColor: Bool {
        let colorStr = config.color.lowercased()
        return ["yellow", "white", "cyan", "lime"].contains(colorStr)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: config.isGrowthStageButton ? "leaf.fill" : "mappin.and.ellipse")
                    .font(.body)

                Text(config.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isLightColor ? .black : .white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(buttonColor.gradient, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
