#!/usr/bin/env bats

@test "fix-perms sets 700 on key dirs and 600 on key files, global and per-project" {
  root="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$root/global/ssh/keys" "$root/projects/acme/ssh/keys" "$root/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$root/bin/fix-perms.sh"
  chmod +x "$root/bin/fix-perms.sh"
  echo "fake" > "$root/global/ssh/keys/id_ed25519"
  chmod 644 "$root/global/ssh/keys/id_ed25519"
  echo "fake" > "$root/projects/acme/ssh/keys/id_ed25519"
  chmod 644 "$root/projects/acme/ssh/keys/id_ed25519"

  run "$root/bin/fix-perms.sh" "$root"
  [ "$status" -eq 0 ]

  [ "$(stat -f '%Lp' "$root/global/ssh/keys")" = "700" ]
  [ "$(stat -f '%Lp' "$root/global/ssh/keys/id_ed25519")" = "600" ]
  [ "$(stat -f '%Lp' "$root/projects/acme/ssh/keys/id_ed25519")" = "600" ]
}

@test "fix-perms does not error when a project has no keys directory yet" {
  root="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$root/global/ssh/keys" "$root/projects/emptyproj/ssh" "$root/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$root/bin/fix-perms.sh"
  chmod +x "$root/bin/fix-perms.sh"

  run "$root/bin/fix-perms.sh" "$root"
  [ "$status" -eq 0 ]
}
