import SwiftUI

/// Quick-add form shown as a card over the bottom of the popover, in every view mode.
struct EventComposer: View {
    @Environment(CalendarModel.self) private var model
    @State private var draft: EventDraft?
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool
    @Environment(\.highlight) private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("New Event")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.selectedDateTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { model.endComposing() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(HoverButtonStyle(size: 22))
                .help(Text("Cancel"))
            }

            if let binding = Binding($draft) {
                form(binding)
            }
        }
        .onAppear {
            draft = model.newDraft()
            // Let the insertion transition start before the field takes focus.
            DispatchQueue.main.async { titleFocused = true }
        }
        .onExitCommand { model.endComposing() }
    }

    @ViewBuilder
    private func form(_ draft: Binding<EventDraft>) -> some View {
        TextField("Title", text: draft.title)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .focused($titleFocused)
            .onSubmit(save)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(0.06))
                    .strokeBorder(highlight.opacity(titleFocused ? 0.7 : 0), lineWidth: 1.5)
            }
            .animation(Motion.hover, value: titleFocused)

        HStack(spacing: 8) {
            Toggle("All Day", isOn: draft.isAllDay.animation(Motion.panel))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
            Spacer(minLength: 0)
            calendarPicker(draft.calendarID)
        }
        .frame(height: 22)

        HStack(spacing: 6) {
            if draft.wrappedValue.isAllDay {
                Label {
                    Text(model.selectedDateTitle)
                } icon: {
                    Image(systemName: "sun.max")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            } else {
                timePicker(draft.start)
                    .onChange(of: draft.wrappedValue.start) { old, new in
                        // Keep the duration when the start moves, like Calendar does.
                        draft.wrappedValue.end = new.addingTimeInterval(draft.wrappedValue.end.timeIntervalSince(old))
                    }
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                timePicker(draft.end)
                    .onChange(of: draft.wrappedValue.end) { _, new in
                        if new < draft.wrappedValue.start { draft.wrappedValue.end = draft.wrappedValue.start }
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)

        HStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Button("Cancel") { model.endComposing() }
                .buttonStyle(CapsuleButtonStyle())
            Button("Add", action: save)
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .disabled(draft.wrappedValue.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.top, 2)
    }

    private func timePicker(_ date: Binding<Date>) -> some View {
        DatePicker("", selection: date, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
    }

    private func calendarPicker(_ selection: Binding<String?>) -> some View {
        Picker("Calendar", selection: selection) {
            ForEach(model.writableCalendarGroups) { group in
                Section(group.title) {
                    ForEach(group.calendars) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(nsImage: item.swatch)
                        }
                        .tag(Optional(item.id))
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    private func save() {
        guard let draft, !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            try model.save(draft)
        } catch {
            withAnimation(Motion.fade) { errorMessage = error.localizedDescription }
        }
    }
}
