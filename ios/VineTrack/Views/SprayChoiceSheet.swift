import SwiftUI

struct SprayChoiceSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let tripId: UUID
    let paddockIds: [UUID]
    var onComplete: () -> Void = {}

    @State private var showSprayProgramList: Bool = false
    @State private var showNewSprayForm: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "spray.and.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(VineyardTheme.leafGreen.gradient)
                        .padding(.top, 24)

                    VStack(spacing: 6) {
                        Text("Add Spray Record")
                            .font(.title2.bold())
                        Text("How would you like to set up this spray?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 24)

                VStack(spacing: 12) {
                    SprayChoiceCard(
                        icon: "list.clipboard",
                        title: "Use a Spray Program Spray",
                        subtitle: "Select from an existing spray configured in the Spray Program",
                        color: .blue,
                        disabled: store.sprayRecords.isEmpty
                    ) {
                        showSprayProgramList = true
                    }

                    SprayChoiceCard(
                        icon: "plus.rectangle.on.rectangle",
                        title: "Create a New Spray Job",
                        subtitle: "Open the Spray Calculator to configure a new spray from scratch",
                        color: VineyardTheme.leafGreen,
                        disabled: false
                    ) {
                        showNewSprayForm = true
                    }
                }
                .padding(.horizontal)

                if store.sprayRecords.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("No spray records yet. Create one using the Spray Calculator first, or start a new spray job.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 16)
                }

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Spray Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        dismiss()
                        onComplete()
                    }
                }
            }
            .sheet(isPresented: $showSprayProgramList, onDismiss: {
                if store.sprayRecord(for: tripId) != nil {
                    dismiss()
                    onComplete()
                }
            }) {
                SprayProgramPickerSheet(tripId: tripId, paddockIds: paddockIds)
            }
            .sheet(isPresented: $showNewSprayForm, onDismiss: {
                if store.sprayRecord(for: tripId) != nil {
                    dismiss()
                    onComplete()
                }
            }) {
                SprayRecordFormView(
                    tripId: tripId,
                    paddockIds: paddockIds
                )
            }
        }
    }
}

private struct SprayChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(disabled ? .secondary : color)
                    .frame(width: 44, height: 44)
                    .background((disabled ? Color.secondary : color).opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(disabled ? .secondary : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
        .disabled(disabled)
    }
}

struct SprayProgramPickerSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let tripId: UUID
    let paddockIds: [UUID]

    private var templateRecords: [SprayRecord] {
        store.sprayRecords.filter { $0.isTemplate }.sorted { $0.sprayReference.lowercased() < $1.sprayReference.lowercased() }
    }

    private var nonTemplateRecords: [SprayRecord] {
        store.sprayRecords.filter { !$0.isTemplate }.sorted { $0.date > $1.date }
    }

    private var availableRecords: [SprayRecord] {
        store.sprayRecords.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableRecords.isEmpty {
                    ContentUnavailableView {
                        Label("No Spray Records", systemImage: "list.bullet.clipboard")
                    } description: {
                        Text("Create spray jobs in the Spray Program first, then select them here.")
                    }
                } else {
                    List {
                        if !templateRecords.isEmpty {
                            Section {
                                ForEach(templateRecords) { record in
                                    Button {
                                        linkRecord(record)
                                    } label: {
                                        SprayProgramPickerRow(record: record, store: store)
                                    }
                                }
                            } header: {
                                Label("Templates", systemImage: "doc.on.doc")
                            } footer: {
                                Text("Templates are reusable — selecting one copies it for this trip and leaves the original in place.")
                            }
                        }

                        if !nonTemplateRecords.isEmpty {
                            Section {
                                ForEach(nonTemplateRecords) { record in
                                    Button {
                                        linkRecord(record)
                                    } label: {
                                        SprayProgramPickerRow(record: record, store: store)
                                    }
                                }
                            } header: {
                                Label("Previous Sprays", systemImage: "clock.arrow.circlepath")
                            } footer: {
                                Text("Select a spray to copy its details to this trip.")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Spray Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func linkRecord(_ source: SprayRecord) {
        let newRecord = SprayRecord(
            tripId: tripId,
            vineyardId: source.vineyardId,
            date: Date(),
            startTime: Date(),
            endTime: nil,
            temperature: source.temperature,
            windSpeed: source.windSpeed,
            windDirection: source.windDirection,
            humidity: source.humidity,
            sprayReference: source.sprayReference,
            tanks: source.tanks,
            notes: source.notes,
            numberOfFansJets: source.numberOfFansJets,
            averageSpeed: nil,
            equipmentType: source.equipmentType,
            tractor: source.tractor,
            tractorGear: source.tractorGear,
            operationType: source.operationType
        )
        store.addSprayRecord(newRecord)

        if var trip = store.trips.first(where: { $0.id == tripId }), trip.isActive {
            trip.totalTanks = newRecord.tanks.count
            store.updateTrip(trip)
        }

        dismiss()
    }
}

private struct SprayProgramPickerRow: View {
    let record: SprayRecord
    let store: DataStore

    private var trip: Trip? {
        store.trips.first(where: { $0.id == record.tripId })
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                if !record.sprayReference.isEmpty {
                    HStack(spacing: 6) {
                        Text(record.sprayReference)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if record.isTemplate {
                            Text("TEMPLATE")
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.12))
                                .clipShape(.capsule)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Label(record.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let paddockName = trip?.paddockName, !paddockName.isEmpty {
                    Label { Text(paddockName) } icon: { GrapeLeafIcon(size: 12) }
                        .font(.caption)
                        .foregroundStyle(VineyardTheme.olive)
                }

                let chemicalNames = record.tanks.flatMap { $0.chemicals }
                    .map { $0.name }
                    .filter { !$0.isEmpty }
                if !chemicalNames.isEmpty {
                    Text(chemicalNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(record.tanks.count) tank\(record.tanks.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !record.equipmentType.isEmpty {
                    Text(record.equipmentType)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
