import SwiftUI

enum ReaderLinks {
    static let privacy = URL(string: "https://tankarr.renzodef.com/privacy")!
    static let support = URL(string: "https://tankarr.renzodef.com/support")!
}

struct PrivacyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmClear = false
    @State private var cleared = false
    var body: some View {
        Form {
            Section("Sul tuo dispositivo") {
                Text("La password del lettore è custodita nel Portachiavi e non viene sincronizzata con iCloud. Indirizzi del server, nome utente, preferenze, ultima pagina letta e segnalibri della demo restano nei dati dell’app; possono essere inclusi nei backup del dispositivo.")
                Text("Copertine e pagine vengono caricate in memoria. L’app non scarica interi libri per la lettura offline.")
            }
            Section("Quando ti colleghi") {
                Text("L’app invia credenziali e richieste di lettura soltanto al server che configuri. Il suo gestore può vedere l’indirizzo IP e le risorse richieste secondo le proprie regole di conservazione. HTTPS verifica il certificato; HTTP è disponibile soltanto sulla rete locale.")
                Text("Quando salvi, sposti o rimuovi un segnalibro, l’app aggiorna il segnalibro della serie sul tuo server Tankarr. Ogni serie ha un solo segnalibro, condiviso con gli altri lettori e dispositivi del server. Il cambio pagina aggiorna soltanto la posizione locale: usa Segnalibro per scegliere la pagina condivisa.")
            }
            Section("Nessun tracciamento") {
                Text("Nessuna pubblicità, SDK di analisi o profilazione. La libreria dimostrativa funziona sul dispositivo, senza account e senza richieste di rete.")
            }
            Section("Gestisci i dati") {
                Text("Disconnetti, nella schermata Connessione, elimina il profilo e la password salvata. Puoi cancellare le posizioni locali, le preferenze di lettura dei volumi e i segnalibri della demo. Per rimuovere un segnalibro dal server usa l’elenco Segnalibri o il menu del lettore.")
                Button("Cancella dati di lettura locali", role: .destructive) { confirmClear = true }
                if cleared { Text("Dati di lettura locali cancellati.").foregroundStyle(.secondary) }
            }
            Section("Informazioni e assistenza") {
                Link("Informativa privacy sul web", destination: ReaderLinks.privacy)
                Link("Assistenza Tankarr Reader", destination: ReaderLinks.support)
                Text("Tankarr Reader 1.0 · Vitoronzo De Francesco").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Privacy e assistenza").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Cancellare posizioni locali, preferenze di lettura e segnalibri della demo?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Cancella dati locali", role: .destructive) { model.clearProgress(); cleared = true }
            } message: { Text("I segnalibri condivisi restano sul server Tankarr.") }
    }
}
