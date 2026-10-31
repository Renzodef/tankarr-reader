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
            Section(L10n.text("Sul tuo dispositivo")) {
                Text(L10n.text("La password del lettore è custodita nel Portachiavi e non viene sincronizzata con iCloud. Indirizzi del server, nome utente, preferenze, ultima pagina letta e segnalibri della demo restano nei dati dell’app; possono essere inclusi nei backup del dispositivo."))
                Text(L10n.text("I download scelti da te restano nell’archivio privato dell’app, protetti dal dispositivo ed esclusi dal backup iCloud. Sono separati per server e account. Puoi rimuoverli da Download senza cancellare nulla sul server."))
            }
            Section(L10n.text("Quando ti colleghi")) {
                Text(L10n.text("L’app invia credenziali e richieste di lettura soltanto al server che configuri. Il suo gestore può vedere l’indirizzo IP e le risorse richieste secondo le proprie regole di conservazione. HTTPS verifica il certificato; HTTP è disponibile soltanto sulla rete locale."))
                Text(L10n.text("Quando salvi, sposti o rimuovi un segnalibro, l’app aggiorna il segnalibro della serie sul tuo server Tankarr. Ogni serie ha un solo segnalibro, condiviso con gli altri lettori e dispositivi del server. Il cambio pagina aggiorna soltanto la posizione locale: usa Segnalibro per scegliere la pagina condivisa."))
            }
            Section(L10n.text("Nessun tracciamento")) {
                Text(L10n.text("Nessuna pubblicità, SDK di analisi o profilazione. La libreria dimostrativa funziona sul dispositivo, senza account e senza richieste di rete."))
            }
            Section(L10n.text("Gestisci i dati")) {
                Text(L10n.text("Disconnetti elimina il profilo, la password e i download dell’account corrente. I progressi di lettura locali si cancellano separatamente. Per rimuovere un segnalibro dal server usa l’elenco Segnalibri o il menu del lettore quando sei connesso."))
                Button(L10n.text("Cancella dati di lettura locali"), role: .destructive) { confirmClear = true }
                if cleared { Text(L10n.text("Dati di lettura locali cancellati.")).foregroundStyle(.secondary) }
            }
            Section(L10n.text("Informazioni e assistenza")) {
                Link(L10n.text("Informativa privacy sul web"), destination: ReaderLinks.privacy)
                Link(L10n.text("Assistenza Tankarr Reader"), destination: ReaderLinks.support)
                Text("Tankarr Reader 1.0 · Vitoronzo De Francesco").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(L10n.text("Privacy e assistenza")).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(L10n.text("Cancellare posizioni locali, preferenze di lettura e segnalibri della demo?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L10n.text("Cancella dati locali"), role: .destructive) { model.clearProgress(); cleared = true }
            } message: { Text(L10n.text("I segnalibri condivisi restano sul server Tankarr.")) }
    }
}
