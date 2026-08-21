#!/usr/bin/env bash
#
# Archives a BirthdayQuest project's Cloud Storage media to a local directory.
#
# WHY THIS EXISTS, AND WHY THE ORDER MATTERS
#
# The event-scoped storage.rules only grant access under events/{eventId}/..., and the
# catch-all at the bottom denies everything else. Once those rules are deployed, any object
# still living under the old top-level rewards/** or proofs/** prefixes is unreachable
# through the app — recoverable only by hand from the Google Cloud console.
#
# So the order is: run this script, verify the counts it prints against the Firebase
# console, and only then run
#
#   firebase deploy --only firestore:rules,storage
#
# usage: tools/export_media.sh <bucket> [destination-dir]
#
#   <bucket>  the STORAGE_BUCKET value from GoogleService-Info.plist, with or without a
#             gs:// prefix (e.g. gs://my-project.firebasestorage.app)
#   [dest]    where to write the archive; defaults to ./bq-media-archive

set -euo pipefail

# The two legacy top-level prefixes. Anything under events/ is already reachable by the new
# rules and does not need archiving.
PREFIXES=(rewards proofs)

die() {
    echo "error: $*" >&2
    exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <bucket> [destination-dir]" >&2
    echo "  <bucket> is the STORAGE_BUCKET value from GoogleService-Info.plist" >&2
    exit 1
fi

command -v gcloud >/dev/null 2>&1 \
    || die "gcloud not found. Install the Google Cloud CLI: https://cloud.google.com/sdk/docs/install"

if [[ -z "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]]; then
    die "no active gcloud account. Run: gcloud auth login"
fi

bucket="${1#gs://}"
bucket="${bucket%/}"
dest="${2:-./bq-media-archive}"

# Probe the bucket itself first. With this confirmed reachable, a later "matched no objects"
# on a prefix can only mean the prefix is genuinely empty — not a typo, not bad credentials.
if ! err=$(gcloud storage ls "gs://$bucket" 2>&1 >/dev/null); then
    die "cannot read gs://$bucket:
$err"
fi

mkdir -p "$dest"
echo "archiving gs://$bucket -> $dest"

copied=0
for prefix in "${PREFIXES[@]}"; do
    if err=$(gcloud storage ls "gs://$bucket/$prefix/" 2>&1 >/dev/null); then
        echo "  copying $prefix/"
        # No error suppression here on purpose: a failed copy must abort the script with
        # gcloud's own message, because "the copy failed" and "there was nothing to copy"
        # need completely different responses from the operator.
        gcloud storage cp -r "gs://$bucket/$prefix" "$dest/"
        copied=$((copied + 1))
    elif [[ "$err" == *"matched no objects"* ]]; then
        echo "  $prefix/ is absent, nothing to copy"
    else
        die "listing gs://$bucket/$prefix/ failed:
$err"
    fi
done

if (( copied == 0 )); then
    cat >&2 <<EOF

NOTHING WAS ARCHIVED. Neither rewards/ nor proofs/ exists in gs://$bucket.

Either the bucket name is wrong, or this project genuinely has no media under the old
top-level paths. Confirm which one in the Firebase console (Storage -> Files) before you
deploy the new rules, because the deploy makes those paths unreachable.
EOF
    exit 1
fi

files=0
bytes=0
while IFS= read -r -d '' file; do
    files=$((files + 1))
    bytes=$((bytes + $(wc -c <"$file")))
done < <(find "$dest" -type f -print0)

awk -v f="$files" -v b="$bytes" -v d="$dest" 'BEGIN {
    printf "\narchived %d files, %d bytes (%.1f MiB) into %s\n", f, b, b / 1048576, d
}'

cat <<'EOF'

Compare that file count against the Firebase console (Storage -> Files). If it does not
match, do not deploy: the new rules deny all access to the old rewards/** and proofs/**
prefixes, and objects left behind are only recoverable from the Google Cloud console.
EOF
