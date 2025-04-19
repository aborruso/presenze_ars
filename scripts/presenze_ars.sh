#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${folder}"/../data
mkdir -p "${folder}"/../data/rawdata
mkdir -p "${folder}"/tmp

#scarica PDF

# Define base URL for the Assembly website
URL="https://www.ars.sicilia.it/amministrazione-trasparente/xviii/altri-contenuti"

# Verifica che il sito sia raggiungibile con timeout più lungo e gestione migliore
if ! curl -s --connect-timeout 30 --max-time 60 -I "$URL" | grep -q "HTTP/[1-2]"; then
  echo "ERRORE: Il sito $URL non è raggiungibile. Uscita."
  exit 1
fi

# Download the page, extract the links to presence PDFs and download each PDF
curl -kL "$URL" |
  scrape -be ".field-items" |
  xq -r '.html.body.div[].a."@href"' |
  grep -iP '.+presenz.+pdf' |
  while read -r line; do
    pdf_url="https://www.ars.sicilia.it$line"
    pdf_name=$(basename "$pdf_url")
    # Decodifica il nome del file per un controllo più affidabile
    decoded_pdf_name=$(printf '%b' "${pdf_name//%/\\x}")
    pdf_path="${folder}/../data/rawdata/${decoded_pdf_name}"

    # Scarica solo se il file non esiste già
    if [ ! -f "$pdf_path" ]; then
      echo "Scarico $decoded_pdf_name"
      # Salva la data odierna nel formato YYYYMMDD
      data_download=$(date +"%Y%m%d")
      # Aggiungi i metadati del PDF scaricato al file di anagrafica
      echo "{\"file\":\"${decoded_pdf_name}\",\"url_download\":\"${pdf_url}\",\"data_download\":\"${data_download}\"}" >>"${folder}"/../data/anagrafica_pdf.jsonl
    else
      echo "Il file $decoded_pdf_name esiste già, salto il download"
    fi
  done

# Rimuove eventuali duplicati dal file di anagrafica
mlr --jsonl uniq -a "${folder}"/../data/anagrafica_pdf.jsonl

# Processa i PDF scaricati ed estrae i dati di presenza
for i in "${folder}"/../data/rawdata/*.pdf; do
  # Calcola l'MD5 del nome del file per usarlo come identificatore univoco
  filename=$(basename "$i")
  md5_name=$(echo -n "$filename" | md5sum | cut -d ' ' -f 1)
  output_jsonl="${folder}/../data/rawdata/${md5_name}.jsonl"

  # Verifica se i dati sono già stati estratti per questo PDF
  if [ -f "$output_jsonl" ]; then
    echo "Il file di output $output_jsonl per $filename esiste già, salto l'elaborazione LLM"
    continue
  fi

  echo "Elaboro $filename con LLM"
  # Usa LLM per estrarre i dati strutturati dal PDF secondo lo schema definito
  llm --schema "${folder}"/../risorse/schema.json -a "$i" | jq -c '.items |= map(. + {file: "'"${filename}"'"}) | .items[]' >"$output_jsonl"
done

# Unisce tutti i file JSONL in un unico file non-sparso
mlr --jsonl unsparsify "${folder}"/../data/rawdata/*.jsonl >"${folder}"/tmp/merged.jsonl

# Applica trasformazioni ai dati:
# - Rinomina la colonna "deputato" in "componente_raw"
# - Pulisce il campo componente rimuovendo asterischi e testo tra parentesi
# - Crea un nuovo campo per ordinamento cronologico basato sul periodo
# - Ordina i dati per periodo (decrescente) e per nome del componente
mlr -I --jsonl --from "${folder}"/tmp/merged.jsonl then rename deputato,componente_raw then put '$componente = sub($componente_raw," *\*+ *$","");$componente = sub($componente," *\(.+$","")' then put '$periodo_sort = splita($periodo, ",");$periodo_sort=$periodo_sort[2]."_".$periodo_sort[1]' then sort -tr periodo_sort -f componente

# Unisce i dati elaborati con l'anagrafica dei PDF, riorganizza le colonne
# e ordina il risultato per periodo e nome del componente
mlr --jsonl join --ul -j file -f "${folder}"/tmp/merged.jsonl then unsparsify then sort -tr periodo_sort -f componente then reorder -f componente,presenze,assenze,congedi_missioni,periodo,componente_raw,periodo_sort,file,url_download,data_download then uniq -a "${folder}"/../data/anagrafica_pdf.jsonl >"${folder}"/tmp/tmp.jsonl

# Salva il risultato finale in formato JSONL
mv "${folder}"/tmp/tmp.jsonl "${folder}"/../data/presenze_ars.jsonl

# Converte il risultato finale anche in formato CSV
mlr --ijsonl --ocsv unsparsify "${folder}"/../data/presenze_ars.jsonl >"${folder}"/../data/presenze_ars.csv

# Svuota la cartella tmp
rm -rf "${folder}"/tmp/*
