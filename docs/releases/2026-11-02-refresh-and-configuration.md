# Aggiornamento, configurazione e continuità dei capitoli

- Connessione: pulsante **Aggiorna Tankarr** con stato di avanzamento ed esito.
- Aggiornamento della libreria nella sessione esistente; annullamenti iOS
  ignorati senza mostrare falsi errori di connessione.
- Export/import JSON di connessione, lingua, opzioni di lettura e serie seguite;
  password e token non vengono esportati. Ripristino delle preferenze legato
  all'identità di account e server.
- Gateway: ordine condiviso fra catalogo e confini dei capitoli, con prologhi
  prima dei capitoli numerati e nessun ritorno ai prologhi dopo l'ultimo.
- Il refresh esplicito invalida la breve cache dei metadati del gateway;
  non avvia scansioni del filesystem né ricerche di nuovi download.

Il Reader mostra soltanto i capitoli già importati sul server. Il numero di
capitoli presenti nelle fonti non equivale a quello dei file leggibili.
Questa versione non attiva download amministrativi dal client in sola lettura.
