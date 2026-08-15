#!/usr/bin/env bash
# Derive per-lab freshness and render the lab index.
#
# Two dates per lab, deliberately kept separate:
#
#   updated    Derived from git. The last *substantive* commit touching the
#              lab. Sweeping edits are ignored, so a repo-wide docs pass does
#              not make every lab look fresh.
#   validated  Asserted in labs.json by whoever last ran the lab against Azure
#              and saw it work. Cannot be derived; a commit is not evidence
#              that anything deploys.
#
# A lab whose `updated` is newer than its `validated` has changed since anyone
# last proved it works — that is the signal worth acting on, and it is why the
# two dates are not collapsed into one.
#
# A commit does not count towards `updated` when it:
#   - touches SWEEP_THRESHOLD or more labs (a repo-wide sweep, not lab work)
#   - carries a `Freshness: skip` trailer (explicit opt-out)
#   - is authored by a bot (dependabot bumps are not lab changes)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

SWEEP_THRESHOLD="${SWEEP_THRESHOLD:-5}"
STALE_AFTER_DAYS="${STALE_AFTER_DAYS:-180}"
LEDGER="labs.json"
SECTIONS=(cloud-native linux)

die() { printf 'lab-freshness: %s\n' "$*" >&2; exit 1; }

[ -f "$LEDGER" ] || die "missing $LEDGER"

# ------------------------------------------------------------ method model --
# `method` records what actually ran, as tokens joined by `+`. Each token is one
# command that succeeded; if it did not run, it is not in the string.
#
# Two ranked tokens form the deployment-evidence track: a real deployment is
# strictly stronger proof than a preview, so recording `deploy` satisfies a
# requirement for `what-if`. Everything else is additive and must be present
# exactly, because those tokens assert different properties rather than
# stronger versions of the same one — `arm-diff` says generated ARM matches its
# source, which is not a weaker form of "it deploys".
#
# `required` states the weakest method that counts as validated. It lives in
# labs.json beside the record so there is one source of truth.
declare -A TOKEN_KNOWN=(
    [what-if]=1 [deploy]=1 [terraform-plan]=1
    [arm-diff]=1 [links]=1 [go-vet]=1 [go-test]=1 [container-build]=1
)
declare -A TOKEN_TRACK=( [what-if]=deployment [deploy]=deployment )
declare -A TOKEN_RANK=(  [what-if]=1          [deploy]=2 )

BLOCK_REASONS='subscription-scope missing-credential out-of-scope tooling-unavailable'

# Every token must be spelled from the vocabulary. An unknown token is a data
# bug, not a lab problem, so it stops the run rather than rendering a row.
validate_method() {
    local where=$1 m=$2 t
    [ -z "$m" ] || [ "$m" = "inferred" ] && return 0
    IFS='+' read -ra toks <<<"$m"
    for t in "${toks[@]}"; do
        [ -n "${TOKEN_KNOWN[$t]:-}" ] || die "$where: unknown method token '$t'"
    done
}

# Does `recorded` meet `required`? Ranked tokens compare by rank within their
# track; unranked tokens must appear verbatim.
satisfies() {
    local recorded=$1 required=$2 t r track need best
    [ -z "$required" ] && return 0
    IFS='+' read -ra req <<<"$required"
    IFS='+' read -ra rec <<<"$recorded"
    for t in "${req[@]}"; do
        track=${TOKEN_TRACK[$t]:-}
        if [ -n "$track" ]; then
            need=${TOKEN_RANK[$t]}; best=0
            for r in "${rec[@]}"; do
                [ "${TOKEN_TRACK[$r]:-}" = "$track" ] || continue
                [ "${TOKEN_RANK[$r]}" -gt "$best" ] && best=${TOKEN_RANK[$r]}
            done
            [ "$best" -ge "$need" ] || return 1
        else
            printf '%s\n' "${rec[@]}" | grep -qxF "$t" || return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------- sweep set --
# One pass over history: which commits touch >= SWEEP_THRESHOLD labs, and which
# opt out explicitly. Done once up front rather than per lab, so the cost stays
# linear in history rather than labs x history.
declare -A EXCLUDED=()

_scan() {
    local commit="" author="" body="" -; local -A labs=()
    while IFS= read -r line; do
        case "$line" in
            $'\x01'*)
                _flush "$commit" "$author" "$body" "$(printf '%s\n' "${!labs[@]}" | grep -c .)"
                IFS=$'\x02' read -r commit author body <<<"${line#$'\x01'}"
                labs=()
                ;;
            "") ;;
            *)
                local lab
                lab=$(printf '%s' "$line" | grep -oE '^('"$(IFS='|'; echo "${SECTIONS[*]}")"')/[^/]+' || true)
                [ -n "$lab" ] && labs["$lab"]=1
                ;;
        esac
    done
    _flush "$commit" "$author" "$body" "$(printf '%s\n' "${!labs[@]}" | grep -c .)"
}

_flush() {
    local commit=$1 author=$2 body=$3 n=$4
    [ -z "$commit" ] && return 0
    if [ "$n" -ge "$SWEEP_THRESHOLD" ]; then
        EXCLUDED["$commit"]="sweep($n labs)"
    elif [[ "$body" == *"Freshness: skip"* ]]; then
        EXCLUDED["$commit"]="opt-out"
    elif [[ "$author" == *"[bot]"* || "$author" == *"dependabot"* ]]; then
        EXCLUDED["$commit"]="bot"
    fi
}

# %x01 marks a commit header; %x02 separates its fields. Neither appears in
# commit text, so the stream stays unambiguous against filenames.
_scan < <(git log --format=$'\x01%H\x02%an\x02%f' --name-only)

# ------------------------------------------------------------------- derive --
last_substantive() {
    local dir=$1 c
    while read -r c; do
        [ -z "$c" ] && continue
        [ -n "${EXCLUDED[$c]:-}" ] && continue
        git log -1 --format='%ad' --date=short "$c"
        return 0
    done < <(git log --format='%H' -- "$dir")
    printf '%s' ""
}

today_epoch=$(date +%s)
days_since() {
    [ -z "$1" ] || [ "$1" = "null" ] && { printf '%s' ""; return; }
    printf '%s' $(( (today_epoch - $(date -d "$1" +%s)) / 86400 ))
}

rows=""
derived=()          # path<TAB>date, for `seed`
counts_ok=0; counts_stale=0; counts_never=0
counts_blocked=0; counts_short=0

for section in "${SECTIONS[@]}"; do
    for dir in "$section"/*/; do
        dir=${dir%/}
        [ -d "$dir" ] || continue

        updated=$(last_substantive "$dir")
        validated=$(jq -r --arg p "$dir" \
            '.labs[] | select(.path==$p) | .last_validated // empty' "$LEDGER")
        method=$(jq -r --arg p "$dir" \
            '.labs[] | select(.path==$p) | .method // empty' "$LEDGER")
        required=$(jq -r --arg p "$dir" \
            '.labs[] | select(.path==$p) | .required // empty' "$LEDGER")
        blocked=$(jq -r --arg p "$dir" \
            '.labs[] | select(.path==$p) | .blocked.reason // empty' "$LEDGER")

        derived+=("$dir"$'\t'"$updated")
        validate_method "$dir" "$method"
        validate_method "$dir (required)" "$required"
        if [ -n "$blocked" ]; then
            printf '%s\n' $BLOCK_REASONS | grep -qxF "$blocked" \
                || die "$dir: unknown blocked reason '$blocked'"
        fi

        if [ -n "$blocked" ]; then
            # A reason explains the gap; it does not excuse it. Blocked labs
            # still fail the gate, so an unvalidatable lab stays visible
            # instead of being parked behind a label.
            status="blocked · $blocked"; counts_blocked=$((counts_blocked+1))
        elif [ -z "$validated" ]; then
            status='never validated'; counts_never=$((counts_never+1))
        elif [ "$method" = "inferred" ]; then
            # Date copied from the last substantive commit, not from a run.
            # Never "ok": nobody has proved this lab deploys.
            status="unvalidated · $(days_since "$validated")d old"
            counts_never=$((counts_never+1))
        elif ! satisfies "$method" "$required"; then
            # Ran something real, but weaker than this lab's bar. Distinct from
            # unvalidated: the gap is in what was checked, not whether.
            status="insufficient · needs $required"; counts_short=$((counts_short+1))
        elif [[ "$updated" > "$validated" ]]; then
            status='changed since validated'; counts_stale=$((counts_stale+1))
        elif [ -n "$(days_since "$validated")" ] \
             && [ "$(days_since "$validated")" -gt "$STALE_AFTER_DAYS" ]; then
            status="ageing (${STALE_AFTER_DAYS}d+)"; counts_stale=$((counts_stale+1))
        else
            status='ok'; counts_ok=$((counts_ok+1))
        fi

        rows+=$(printf '| [`%s`](./%s/) | %s | %s | %s | %s |\n' \
            "$dir" "$dir" "${updated:-—}" "${validated:-—}" "${method:-—}" "$status")
        rows+=$'\n'
    done
done

case "${1:-render}" in
    render)
        printf '| Lab | Updated | Validated | Method | Status |\n'
        printf '| --- | --- | --- | --- | --- |\n'
        printf '%s' "$rows"
        printf '\n_%s validated, %s need attention, %s never validated, %s insufficient, %s blocked._\n' \
            "$counts_ok" "$counts_stale" "$counts_never" "$counts_short" "$counts_blocked"
        ;;
    check)
        if [ $((counts_stale + counts_never + counts_short + counts_blocked)) -gt 0 ]; then
            printf '%s' "$rows" | grep -vE '\| ok \|$' >&2 || true
            die "$counts_stale changed-or-ageing, $counts_never never validated, $counts_short insufficient, $counts_blocked blocked"
        fi
        printf 'lab-freshness: all %s labs validated and current\n' "$counts_ok"
        ;;
    seed)
        # Backfill last_validated from each lab's last substantive commit,
        # marked method=inferred so the table never reports it as validated.
        # It only gives the Validated column a date, making staleness legible
        # before anyone has run anything. A real `just validated` record is
        # never overwritten — only null and previously-inferred entries move.
        n=0
        for pair in "${derived[@]}"; do
            p=${pair%%$'\t'*}; d=${pair#*$'\t'}
            [ -n "$d" ] || continue
            # Skip entries carrying a real validation, so the count reflects
            # rows actually moved rather than rows visited.
            jq -e --arg p "$p" '.labs[] | select(.path==$p and
                (.last_validated==null or .method=="inferred"))' \
                "$LEDGER" >/dev/null || continue
            jq --arg p "$p" --arg d "$d" '
                (.labs[] | select(.path==$p and
                                  (.last_validated==null or .method=="inferred")))
                  |= (.last_validated=$d | .method="inferred" | .validated_by=null)
            ' "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
            n=$((n+1))
        done
        printf 'lab-freshness: seeded %s labs from commit dates (method=inferred)\n' "$n"
        ;;
    *) die "usage: lab-freshness.sh [render|check|seed]" ;;
esac
