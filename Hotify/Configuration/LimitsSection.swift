import CoolifyAPI
import SwiftUI

/// How many CPUs and how much memory an application's container may use. An empty field lifts the limit.
struct LimitsSection: View {
    @Binding var limits: ApplicationLimits

    /// Digits and one decimal separator. The value is checked as a whole before saving.
    private var cpus: Binding<String> {
        Binding(
            get: { limits.cpus },
            set: { limits.cpus = $0.filter { ($0.isASCII && $0.isNumber) || $0 == "." || $0 == "," } }
        )
    }

    private var memory: Binding<String> {
        Binding(
            get: { limits.memory.map(String.init) ?? "" },
            set: { limits.memory = Int($0.filter(\.isASCII).filter(\.isNumber)) }
        )
    }

    var body: some View {
        Section {
            LabeledContent("CPUs") {
                TextField("CPUs", text: cpus, prompt: Text("No limit"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    #if os(iOS)
                .keyboardType(.decimalPad)
                    #endif
                    .frame(maxWidth: 110)
            }
            LabeledContent("Memory") {
                HStack(spacing: 4) {
                    TextField("Memory", text: memory, prompt: Text("No limit"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        #if os(iOS)
                    .keyboardType(.numberPad)
                        #endif
                        .frame(maxWidth: 110)
                    Picker("Unit", selection: $limits.memoryUnit) {
                        ForEach(limits.memoryUnits, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        } header: {
            Text("Resources")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "Leave a field empty for no limit. Changes take effect with the next deployment."
        switch (limits.memoryReservation, limits.memorySwap) {
        case (let reservation?, let swap?):
            text +=
                " Coolify also keeps a soft limit of \(reservation) and caps memory and swap together at \(swap). Change those in Coolify."
        case (let reservation?, nil):
            text += " Coolify also keeps a soft limit of \(reservation). Change it in Coolify."
        case (nil, let swap?):
            text += " Coolify also caps memory and swap together at \(swap). Change that in Coolify."
        case (nil, nil):
            break
        }
        return text
    }
}

#Preview("Limited") {
    @Previewable @State var limits = ApplicationLimits(
        limits: ResourceLimits(cpus: "1.5", memory: "512m", memorySwap: "1g", memoryReservation: "256m"))
    Form {
        LimitsSection(limits: $limits)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 280)
}

#Preview("No limits") {
    @Previewable @State var limits = ApplicationLimits(limits: ResourceLimits(cpus: "0", memory: "0"))
    Form {
        LimitsSection(limits: $limits)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 240)
}
