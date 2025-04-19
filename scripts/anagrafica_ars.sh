#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${folder}"/../data
mkdir -p "${folder}"/../data/rawdata
mkdir -p "${folder}"/../data/anagrafica
mkdir -p "${folder}"/tmp

# Scarica la pagina della XVIII legislatura e estrae l'anagrafica dei deputati (URL personale, nome e gruppo)
curl -kL "https://www.ars.sicilia.it/xviii-legislatura" | scrape -be 'a:has(p.nome)' | xq -c '.html.body.a[] | {url: ."@href", cognome_nome: .div[1].div.p[0]."#text", gruppo: .div[1].div.p[1]."#text"}' > "${folder}"/tmp/anagrafica_ars.jsonl

# Aggiunge il dominio base agli URL
mlr -I --jsonl put '$url="https://www.ars.sicilia.it".$url' "${folder}"/tmp/anagrafica_ars.jsonl

# Salva il file di base con i dati grezzi
mv "${folder}"/tmp/anagrafica_ars.jsonl "${folder}"/../data/anagrafica/componenti_ars.jsonl

# Estrae cognome, nome e sesso da ogni record usando LLM
mlr --jsonl cut -f cognome_nome "${folder}"/../data/anagrafica/componenti_ars.jsonl | llm -m gemini-2.5-pro-exp-03-25 --schema-multi "cognome: estrai soltanto il cognome da cognome_nome, nome: estrai soltanto il nome cognome_nome,sesso: inserisci maschio o femmina o N/A quando non applicabile o non chiaro,cognome_nome: lascia il dato originale" >"${folder}"/../data/anagrafica/componenti_ars_info_estratte.jsonl

# Riorganizza l'output di LLM in formato JSONL standard
<"${folder}"/../data/anagrafica/componenti_ars_info_estratte.jsonl jq -c '.items[]' >"${folder}"/tmp/tmp.jsonl

mv "${folder}"/tmp/tmp.jsonl "${folder}"/../data/anagrafica/componenti_ars_info_estratte.jsonl

# Unisce i dati originali con le informazioni estratte da LLM
mlr --jsonl join --ul -j cognome_nome -f "${folder}"/../data/anagrafica/componenti_ars.jsonl then unsparsify "${folder}"/../data/anagrafica/componenti_ars_info_estratte.jsonl >"${folder}"/tmp/tmp.jsonl

mv "${folder}"/tmp/tmp.jsonl "${folder}"/../data/anagrafica/componenti_ars.jsonl

# Esporta il risultato anche in formato CSV
mlr --ijsonl --ocsv unsparsify "${folder}"/../data/anagrafica/componenti_ars.jsonl >"${folder}"/../data/anagrafica/componenti_ars.csv
