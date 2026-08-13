default:
    @just --list

# Print the lab freshness index
index:
    @./scripts/lab-freshness.sh render

# Fail if any lab is unvalidated, changed since validation, or ageing
index-check:
    @./scripts/lab-freshness.sh check

# Record that a lab was validated today: just validated cloud-native/aks-arm what-if
validated path method="what-if" by="":
    #!/usr/bin/env bash
    set -euo pipefail
    who="{{ by }}"
    [ -n "$who" ] || who=$(git config user.name)
    jq --arg p "{{ path }}" --arg d "$(date +%F)" --arg m "{{ method }}" --arg w "$who" \
      '(.labs[] | select(.path==$p)) |=
         (.last_validated=$d | .method=$m | .validated_by=$w)' \
      labs.json > labs.json.tmp
    if ! jq -e --arg p "{{ path }}" '.labs[] | select(.path==$p)' labs.json.tmp >/dev/null; then
        rm -f labs.json.tmp; echo "no such lab: {{ path }}" >&2; exit 1
    fi
    mv labs.json.tmp labs.json
    ./scripts/lab-freshness.sh render | grep -F '[`{{ path }}`]'
