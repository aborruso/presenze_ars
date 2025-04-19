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
      wget -O "$pdf_path" "$pdf_url"
    else
      echo "Il file $decoded_pdf_name esiste già, salto il download"
    fi
  done

# Processa i PDF solo se il file JSONL di output non esiste già
for i in "${folder}"/../data/rawdata/*.pdf; do
  # Calcola l'MD5 del nome del file per usarlo come nome file di output
  filename=$(basename "$i")
  md5_name=$(echo -n "$filename" | md5sum | cut -d ' ' -f 1)
  output_jsonl="${folder}/../data/rawdata/${md5_name}.jsonl"

  # Se il file JSONL esiste già, salta questo PDF
  if [ -f "$output_jsonl" ]; then
    echo "Il file di output $output_jsonl per $filename esiste già, salto l'elaborazione LLM"
    continue
  fi

  echo "Elaboro $filename con LLM"
  # Comando LLM per processare il PDF
  llm --schema "${folder}"/../risorse/schema.json -a "$i" | jq -c '.items |= map(. + {file: "'"${filename}"'"}) | .items[]' > "$output_jsonl"
done
