#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
app=~/Applications/CDPlayer.app/Contents/MacOS/CDPlayer
store=/tmp/CDPlayer-test.store
shots=/tmp/CDPlayer-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/${BUNDLE_ID:-io.github.enriquegpz.xenon}.savedState
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
