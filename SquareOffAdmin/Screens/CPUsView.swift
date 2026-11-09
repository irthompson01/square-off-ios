import Charts
import SquareOffNet
import SwiftUI

/// One card per CPU definition: level, usage, human win rate, think time, a usage sparkline,
/// a test move and the editor (web `pages/admin/cpus.tsx`).
struct CPUsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var rows: AdminQuery<[AdminCPURow]>?
    @State private var stats: AdminQuery<AdminCPUStatsResponse>?
    @State private var days = 30
    @State private var editing: AdminCPURow?
    @State private var creating = false
    @State private var deleting: AdminCPURow?
    @State private var testResults: [String: String] = [:]
    @State private var testing: Set<String> = []

    private let periods = [7, 30, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "CPUs", description: "The opponents players can pick, how often they're used and how they do.")
                HStack {
                    SegmentedPills(options: periods.map(Period.init), selection: Binding(get: { Period(days: days) }, set: { days = $0.days }), title: { "\($0.days) d" }, compact: true)
                        .frame(maxWidth: 240)
                    Spacer()
                    Button { creating = true } label: { Label("Add CPU", systemImage: "plus") }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                }
                if let rows {
                    if let error = rows.error, rows.value == nil {
                        SectionError(message: error) { Task { await rows.refresh() } }
                    } else if let cpus = rows.value {
                        ForEach(cpus) { cpu in card(cpu, stats: stats?.value?.items.first { $0.id == cpu.id }) }
                    } else {
                        SkeletonRows().padding(16).card()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("CPUs")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await rows?.refresh(); await stats?.refresh() }
        .onAppear { if rows == nil { let api = app.admin; rows = AdminQuery { try await api.cpus() } } }
        .task { await rows?.refresh() }
        .task(id: days) {
            let api = app.admin, days = days
            stats = AdminQuery { try await api.cpuStats(days: days, tz: TimeZone.current.identifier) }
            await stats?.refresh()
        }
        .sheet(item: $editing) { cpu in CPUEditorSheet(existing: cpu) { Task { await rows?.refresh() } }.presentationBackground(Theme.overlay) }
        .sheet(isPresented: $creating) { CPUEditorSheet(existing: nil) { Task { await rows?.refresh() } }.presentationBackground(Theme.overlay) }
        .alert("Delete \(deleting?.displayName ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let cpu = deleting { delete(cpu) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The server refuses when the CPU appears in game history.") }
    }

    private struct Period: Hashable, Identifiable {
        let days: Int
        var id: Int { days }
    }

    private func card(_ cpu: AdminCPURow, stats: AdminCPUStats?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: cpu.color)).frame(width: 12, height: 12)
                Text(cpu.displayName).font(Theme.display(16, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                Chip(text: cpu.cpuType)
                if cpu.isPremium { Chip(text: "Premium", style: .warning) }
                Spacer()
                Menu {
                    Button("Edit") { editing = cpu }
                    Button("Games with this CPU") { console.section = .games }
                    Button("Delete", role: .destructive) { deleting = cpu }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.foregroundSecondary).frame(width: 32, height: 32) }
            }
            if let description = cpu.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(Theme.foregroundSecondary)
            }
            HStack(spacing: 10) {
                Stat(label: "Games", value: "\(stats?.gamesTotal ?? cpu.usageCount)", size: 18).frame(maxWidth: .infinity, alignment: .leading)
                Stat(label: "Human wins", value: AdminFormat.percent(stats?.humanWinRate), size: 18).frame(maxWidth: .infinity, alignment: .leading)
                Stat(label: "Avg think", value: stats?.avgHumanThinkS.map { String(format: "%.1f s", $0) } ?? "—", size: 18).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let usage = stats?.usageByDay, usage.contains(where: { $0.count > 0 }) {
                Chart(usage) { day in
                    BarMark(x: .value("Day", day.date), y: .value("Games", day.count)).foregroundStyle(Theme.link)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
                .accessibilityLabel("\(stats?.gamesTotal ?? 0) games in the last \(days) days")
            }
            HStack(spacing: 10) {
                Button {
                    testing.insert(cpu.cpuType)
                    Task {
                        defer { testing.remove(cpu.cpuType) }
                        do {
                            let move = try await app.admin.testMove(cpuType: cpu.cpuType, boardSize: 8)
                            testResults[cpu.cpuType] = "(\(move.row), \(move.col)) in \(Int(move.latencyMs)) ms"
                        } catch {
                            testResults[cpu.cpuType] = AdminErrors.message(for: error)
                        }
                    }
                } label: { PendingLabel(title: "Test move", pendingTitle: "Asking…", symbol: "bolt", isPending: testing.contains(cpu.cpuType)) }
                    .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                    .disabled(testing.contains(cpu.cpuType))
                if let result = testResults[cpu.cpuType] {
                    Text(result).font(.caption).monospacedDigit().foregroundStyle(Theme.foregroundSecondary)
                }
            }
        }
        .padding(16)
        .card()
    }

    private func delete(_ cpu: AdminCPURow) {
        Task {
            do {
                _ = try await app.admin.deleteCPU(id: cpu.id)
                app.toasts.success("CPU deleted")
                await rows?.refresh()
            } catch {
                app.toasts.danger("Couldn't delete the CPU", description: AdminErrors.message(for: error))
            }
        }
    }
}

struct CPUEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let existing: AdminCPURow?
    let onDone: () -> Void

    @State private var id = ""
    @State private var cpuType = ""
    @State private var displayName = ""
    @State private var description = ""
    @State private var colorHex = Theme.playerColors[1]
    @State private var isPremium = false
    @State private var error: String?
    @State private var pending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error { AlertBox(.danger, title: "Couldn't save", message: error) }
                    if existing == nil {
                        LabeledField(label: "Id", help: "Also the setup level number.") { TextField("7", text: $id).keyboardType(.numberPad).foregroundStyle(Theme.foreground) }
                        LabeledField(label: "CPU type", help: "What the move endpoint is asked for, e.g. max-min-io.") { TextField("cpu-type", text: $cpuType).textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(Theme.foreground) }
                    }
                    LabeledField(label: "Display name") { TextField("Level 7 · Name", text: $displayName).foregroundStyle(Theme.foreground) }
                    LabeledField(label: "Description") { TextField("Optional", text: $description).foregroundStyle(Theme.foreground) }
                    HStack(spacing: 10) {
                        Text("Color").font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                        ColorSwatchPicker(selection: $colorHex, allowCustom: true)
                    }
                    SettingsToggle(title: "Premium", description: "Needs an entitlement to pick.", isOn: $isPremium)
                    Button(action: save) { PendingLabel(title: existing == nil ? "Create CPU" : "Save changes", pendingTitle: "Saving…", symbol: nil, isPending: pending) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(pending || displayName.trimmingCharacters(in: .whitespaces).isEmpty || (existing == nil && (Int(id) == nil || cpuType.isEmpty)))
                }
                .padding(20)
            }
            .background(Theme.overlay)
            .navigationTitle(existing == nil ? "Add CPU" : "Edit CPU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(pending) } }
        }
        .onAppear {
            guard let existing else { return }
            displayName = existing.displayName
            description = existing.description ?? ""
            colorHex = existing.color
            isPremium = existing.isPremium
        }
    }

    private func save() {
        pending = true
        error = nil
        Task {
            defer { pending = false }
            do {
                if let existing {
                    _ = try await app.admin.patchCPU(id: existing.id, AdminCPUPatch(
                        displayName: displayName != existing.displayName ? displayName : nil, color: colorHex != existing.color ? colorHex : nil,
                        description: description != (existing.description ?? "") ? description : nil, isPremium: isPremium != existing.isPremium ? isPremium : nil))
                } else {
                    _ = try await app.admin.createCPU(AdminCPUCreate(id: Int(id) ?? 0, cpuType: cpuType, displayName: displayName, color: colorHex,
                                                                     description: description.isEmpty ? nil : description, isPremium: isPremium))
                }
                dismiss()
                app.toasts.success(existing == nil ? "CPU created" : "CPU updated")
                onDone()
            } catch {
                self.error = AdminErrors.message(for: error)
            }
        }
    }
}
