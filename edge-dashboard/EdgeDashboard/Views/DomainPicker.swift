import SwiftUI

struct DomainPicker: View {
    @Binding var domain: Domain

    var body: some View {
        Picker("Domain", selection: $domain) {
            ForEach(Domain.allCases) { d in
                Text(d.label).tag(d)
            }
        }
        .pickerStyle(.menu)
    }
}
