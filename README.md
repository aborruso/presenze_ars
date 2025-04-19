# Monitoraggio Presenze ARS

Questo repository contiene uno script per il monitoraggio automatico delle presenze e assenze dei deputati dell'Assemblea Regionale Siciliana (ARS).

## Descrizione

Lo script `scripts/presenze_ars.sh` si occupa di:

1. Scaricare automaticamente i PDF delle presenze dalla sezione "Amministrazione Trasparente" del sito dell'ARS
2. Tenere traccia dei file scaricati e dei loro metadati
3. Processare i PDF per estrarne i dati in formato strutturato
4. Unire e normalizzare i dati in un unico dataset
5. Produrre output in formato JSON Lines (`.jsonl`) e CSV

## Output

Lo script genera diversi file nella cartella `data/`:

- [`anagrafica_pdf.jsonl`](data/anagrafica_pdf.jsonl): contiene i metadati dei PDF scaricati (nome file, URL, data di download)
- [`presenze_ars.jsonl`](data/presenze_ars.jsonl): dataset completo in formato JSON Lines
- [`presenze_ars.csv`](data/presenze_ars.csv): dataset completo in formato CSV

I dati grezzi e i PDF originali sono conservati nella cartella `data/rawdata/`.

## Struttura dei dati

Per ogni deputato vengono raccolte le seguenti informazioni:

- Nome del componente
- Numero di presenze
- Numero di assenze
- Numero di congedi/missioni
- Periodo di riferimento

## Requisiti

Lo script utilizza i seguenti strumenti:

- `curl` per il download dei file
- `scrape` e `xq` per l'elaborazione HTML
- `mlr` (Miller) per la manipolazione dei dati
- `llm` per l'estrazione dei dati dai PDF
- `jq` per la manipolazione JSON

## Note

- I dati sono disponibili sia in formato JSON Lines che CSV per massima interoperabilità
