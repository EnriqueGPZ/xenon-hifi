#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/${BUNDLE_ID:-io.github.enriquegpz.xenon}.savedState
store=/tmp/CDPlayer-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/CDPlayer.app/Contents/MacOS/CDPlayer --selftest
