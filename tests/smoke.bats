#!/usr/bin/env bats
# ABOUTME: Smoke test that the image's shared shell library is in place.
# ABOUTME: Real behaviour tests live in the other tests/*.bats files.

@test "lib.sh exists" {
  [ -f stage-shulportal/01-shulportal/files/usr/local/lib/shulportal/lib.sh ]
}
