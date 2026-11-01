# Download interattivi nella serie

- Sorgenti: [`c82486e`](https://github.com/Renzodef/tankarr-reader/commit/c82486ecb80c77c1f0e5ebabf82ec15f0c30356a).
- [Pipeline di verifica e TestFlight](https://github.com/Renzodef/tankarr-reader/actions/runs/41274526121).

## Modifica

La pagina della serie mostra sotto ogni capitolo gli stessi indicatori della
schermata Download globale: barra, percentuale, pagine salvate sul totale,
spazio occupato, posizione nella selezione, pausa, completamento ed errori.
Un riepilogo indica quanti libri sono completi e quanti restano in coda.
Anche un libro che aspetta ancora i metadati mostra il proprio stato in coda.

Il pulsante accanto al capitolo mette in pausa o riprende; dopo il completamento
permette di rimuovere la copia locale. Lo scorrimento laterale offre la rimozione
con conferma anche per i download incompleti. Pausa e ripresa hanno etichette
accessibili distinte e testi italiani/inglesi.

`DownloadBookProgress` è condiviso dalle due schermate e osserva direttamente
`DownloadManager`. Cambiare pagina non crea un'altra coda, non azzera il
conteggio e non avvia un secondo trasferimento. I nuovi metodi del manager
leggono ordine e numero degli elementi senza cambiare il motore dei download
in background o il formato del journal persistente.

## Verifica

Prima del push: 94 test Python e 56 Swift riusciti. La prova UI mirata su
iPhone 17 simula pagine lente da un server locale e controlla avanzamento
nella serie, pausa, stesso conteggio nella lista globale, ritorno nella serie,
ripresa, completamento e rimozione di un solo capitolo mantenendo l'altro.
Controllata anche la schermata acquisita durante il download.

La suite completa su iPhone 17 ha concluso **12 prove con zero errori** il
1 novembre 2026 alle **06:03:41 CET** (Europe/Rome).

La suite iPad ha concluso **12 prove con zero errori** alle **06:17:30 CET**.
Archivio, esportazione e upload riusciti. **1.0.0 (10)** distribuita al gruppo
TestFlight interno alle **06:25:39 CET**; stato Apple `VALID` / `IN_BETA_TESTING`
e note italiane/inglesi verificati tramite API. Nessuna modifica al server
Tankarr o all'invio App Store esistente.
