import SwiftUI

/// Shared confirmation and result feedback for the list and event detail bells.
private struct SkyEventReminderConfirmation: ViewModifier {
    let event: SkyEvent?
    let store: SkyEventStore
    @Binding var isPresented: Bool
    @State private var showsResult = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""

    private var isOn: Bool { event.map { store.reminders.contains($0.id) } ?? false }

    func body(content: Content) -> some View {
        content
            .alert(
                isOn ? "Turn off reminder?" : "Turn on reminder?",
                isPresented: $isPresented, presenting: event
            ) { event in
                Button(isOn ? "Turn Off Reminder" : "Add to iPhone Reminders",
                       role: isOn ? .destructive : nil) {
                    let enabled = !isOn
                    Task {
                        do {
                            try await store.setReminder(enabled, for: event)
                            resultTitle = enabled ? "Reminder added" : "Reminder turned off"
                            resultMessage = enabled
                                ? "\(event.title) was added to Reminders with an alert when viewing begins."
                                : "The reminder for \(event.title) was removed from iPhone Reminders."
                        } catch {
                            resultTitle = "Couldn't update reminder"
                            resultMessage = error.localizedDescription
                        }
                        showsResult = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { event in
                if isOn {
                    Text("Remove the Asterra reminder for \(event.title) from iPhone Reminders?")
                } else {
                    Text("Add \(event.title) to Reminders and alert you when viewing begins?\n\n\(event.collectWindow)")
                }
            }
            .alert(resultTitle, isPresented: $showsResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
    }
}

extension View {
    func skyEventReminderConfirmation(
        event: SkyEvent?, store: SkyEventStore, isPresented: Binding<Bool>
    ) -> some View {
        modifier(SkyEventReminderConfirmation(event: event, store: store, isPresented: isPresented))
    }
}
