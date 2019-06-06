#!/bin/bash
#
# clones latest PeeringDB projects to be translated and adds to the
# translation files, and suggests commit command.
#
# Meant to only be run on the trans0 instance.
#

TMP_DIR=`mktemp -d /tmp/pdblocale.XXXXXXXX`
#MAKEMSG_OPTIONS="--all --symlinks --no-wrap --keep-pot"
MAKEMSG_OPTIONS="--all --symlinks --no-wrap --no-location --keep-pot"
WLC="/srv/translate.peeringdb.com/venv/bin/wlc"
WORK_DIR="/srv/translate.peeringdb.com/data/vcs/peeringdb/server"

function clean_up() {
    error_code=$?  # this needs to be here to catch the intended exit code
    set +x
    $WLC unlock peeringdb/server
    $WLC unlock peeringdb/javascript
    rm -rf "$TMP_DIR"
    rm -f peeringdb_server
    rm -f django_peeringdb
    echo
    echo exiting with $error_code
    exit $error_code
}

trap clean_up EXIT

PDB_TREE="/srv/translate.peeringdb.com"
if [ ! -d $PDB_TREE ]; then
    echo This script is only meant to be run on trans0.peeringdb.com.
    echo Instead run \"update-master.sh\" on production and beta masters.
    exit 1
fi
PDB_BIN="$PDB_TREE/venv/bin"

cd $WORK_DIR || exit 1

(
cd $TMP_DIR
git clone https://github.com/peeringdb/peeringdb.git
git clone https://github.com/peeringdb/django-peeringdb.git
)

server_head=`git --git-dir=$TMP_DIR/peeringdb/.git rev-parse --short HEAD`
django_head=`git --git-dir=$TMP_DIR/django-peeringdb/.git rev-parse --short HEAD`

ln -s $TMP_DIR/peeringdb/peeringdb_server || exit 1
ln -s $TMP_DIR/django-peeringdb/django_peeringdb || exit 1

echo
echo If \"duplicate message definition\" errors in the below, edit indicated file by removing duplicate that _does_not_ already have a translation, even if commented out.  Then re-run $0 manually.
echo

# Guidance from https://docs.weblate.org/en/latest/admin/continuous.html
$WLC lock peeringdb/server || exit 1 
$WLC lock peeringdb/javascript || exit 1 
$WLC push || exit 1 # Push changes from Weblate to upstream repository

set -x
$PDB_BIN/django-admin makemessages $MAKEMSG_OPTIONS || exit 1
$PDB_BIN/django-admin makemessages $MAKEMSG_OPTIONS --domain djangojs || exit 1
set +x

# Remove these since no longer needed and we don't want them accidentally added to the repo.
rm -f peeringdb_server
rm -f django_peeringdb

# Remove "POT-Creation-Date:" lines from both .po and .pot files, so that we don't have a diff every run.
find $WORK_DIR -name *.po* -print0 | xargs -0 sed -i /^\"POT-Creation-Date:/d || exit 1

echo
echo Fix any compilemessages messages errors indicated below on the https://translate.peeringdb.com/ site and then re-run $0 manually.
echo
$PDB_BIN/django-admin compilemessages || exit 1

git add locale || exit 1
# Deduce whether to perfom a commit:
[[ -z $(git status --untracked-files=no --porcelain) ]] || git commit -m "new translations (server:$server_head django:$django_head)" || exit 1

$WLC push || exit 1 # Push changes from Weblate to upstream repository
$WLC pull || exit 1 # Tell Weblate to pull changes

# Weblate unlocks are done as part of exit routine auto-cleanup.

