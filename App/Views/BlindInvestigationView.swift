import SwiftUI

struct BlindInvestigationView: View {
    @ObservedObject var runtime: Runtime
    @State private var blindID = ""
    @State private var search = ""
    @State private var target = 50.0
    @State private var travel = 60.0
    @State private var markedAt: Date?
    @State private var markerMessage = ""

    private var blinds: [AccessoryRecord] {
        runtime.inventory?.accessories.filter {
            $0.services.flatMap(\.characteristics).contains { $0.type == "0000006D-0000-1000-8000-0026BB765291" }
        } ?? []
    }

    private func roomName(for blind: AccessoryRecord) -> String {
        guard let roomID = blind.roomID else { return "No room" }
        return runtime.inventory?.rooms.first(where: { $0.id == roomID })?.name ?? "Unknown room"
    }

    private var filteredBlinds: [AccessoryRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return blinds }
        return blinds.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.manufacturer ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.model ?? "").localizedCaseInsensitiveContains(query) ||
            roomName(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedReading: BlindPositionReading? { runtime.blindReadings[blindID] }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            Text("Record a blind command").font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Mark a test here, then issue the same command in Apple Home or with the remote. This app reads HomeKit-reported position; you confirm whether the blind physically moves.")
                .foregroundStyle(ObserverStyle.secondaryText)
            if blinds.isEmpty {
                ObserverEmptyState("No blinds in the inventory", description: Text("Choose a Home and wait for a complete inventory before recording a test."))
            } else {
                TextField("Find a blind", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter blinds")
                if filteredBlinds.isEmpty {
                    ObserverEmptyState("No matching blinds", description: Text("Try another name, room, or model."))
                }
                GroupBox("Reproduction marker") {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("Blind", selection: $blindID) {
                            Text("Choose a blind").tag("")
                            ForEach(filteredBlinds) { blind in
                                Text("\(blind.name) · \(roomName(for: blind))").tag(blind.id)
                            }
                        }
                        .disabled(filteredBlinds.isEmpty)
                        GroupBox("Latest reported position") {
                            VStack(alignment: .leading, spacing: 10) {
                                if let selectedReading {
                                    LabeledContent("Current position", value: selectedReading.current.map { "\(Int($0.rounded()))%" } ?? "Not reported")
                                    LabeledContent("HomeKit target", value: selectedReading.target.map { "\(Int($0.rounded()))%" } ?? "Not reported")
                                    LabeledContent("Last HomeKit update", value: selectedReading.updatedAt.formatted(date: .abbreviated, time: .standard))
                                } else {
                                    Label("Waiting for a HomeKit position read", systemImage: "clock")
                                        .foregroundStyle(ObserverStyle.secondaryText)
                                    Text("Read now before marking the test so the current position is recorded.")
                                        .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                                }
                                if !blindID.isEmpty {
                                    Button("Read HomeKit Position Now") { runtime.adapter.readPositions() }
                                } else {
                                    Text("Choose a blind to read its position.")
                                }
                                LabeledContent("Observed command outcome", value: runtime.blindOutcomes[blindID]?.title ?? "No active test")
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                        Text("These are reported characteristic values, not proof of physical movement.")
                            .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Requested position", value: "\(Int(target))%")
                            Slider(value: $target, in: 0...100, step: 1) {
                                Text("Requested position")
                            } minimumValueLabel: { Text("0%") } maximumValueLabel: { Text("100%") }
                            .accessibilityValue("\(Int(target)) percent")
                        }
                        HStack {
                            Text("Measured full travel time")
                            Spacer()
                            TextField("Seconds", value: $travel, format: .number)
                                .multilineTextAlignment(.trailing).frame(maxWidth: 90)
                                .accessibilityLabel("Measured full travel time in seconds")
                            Text("seconds").foregroundStyle(ObserverStyle.secondaryText)
                        }
                        Text("Use a measured value from 1 to 600 seconds. The timeout allows an extra 15 seconds and a 5% position tolerance.")
                            .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                        Button("Mark Command Now") {
                            if runtime.mark(blindID, target: target, travel: travel) {
                                markedAt = Date()
                                markerMessage = "Marker recorded. Issue the matching command in Apple Home or with the remote now."
                            } else {
                                markerMessage = "A current HomeKit position is not available yet. Read the blind position and try again."
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ObserverStyle.solidButtonTint)
                        .foregroundStyle(.primary)
                        .disabled(blindID.isEmpty || selectedReading?.current == nil || !travel.isFinite || !(1...600).contains(travel) || runtime.busy)
                        if let markedAt {
                            Label("Marker recorded at " + markedAt.formatted(date: .omitted, time: .standard), systemImage: "checkmark.circle")
                                .accessibilityIdentifier("observer.marker")
                        }
                        if !markerMessage.isEmpty { Text(markerMessage).font(.callout).foregroundStyle(ObserverStyle.secondaryText) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            GroupBox("What to record") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Compare one failing blind and one working blind. Note the command source, requested position, displayed position, actual movement, and time.")
                    Text("A position update does not prove movement. An Apple Home failure with a successful remote or Home Assistant command narrows the investigation, but does not identify the cause by itself.")
                        .foregroundStyle(ObserverStyle.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
        .onChange(of: blindID) { _, _ in markedAt = nil; markerMessage = "" }
        .onChange(of: runtime.selectedID) { _, _ in blindID = ""; markedAt = nil; markerMessage = "" }
    }
}
