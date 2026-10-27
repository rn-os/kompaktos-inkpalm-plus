# Shared helpers for the InkPalm+ post-install tools (zsh; source it, no side effects on load).
# Used by tools/regress.sh --quick and tools/install-inkpalmplus.sh.

IPP_RELEASE_SHA256=782af53e90cdf97532fd88cf5ac0c771a4a58f1a76a63e87745e018b2a2d1d7a

# ipp_apksigner: print the path of an apksigner (PATH, then the newest Android SDK build-tools), or nothing.
ipp_apksigner() {
  local p sdk d
  p=$(command -v apksigner 2>/dev/null) && { print -r -- $p; return 0; }
  for sdk in ${ANDROID_HOME:-} ${ANDROID_SDK_ROOT:-} $HOME/Library/Android/sdk $HOME/Android/Sdk; do
    [[ -n $sdk ]] || continue
    d=(${sdk}/build-tools/*/apksigner(N.On))     # newest version name last after reverse-order sort
    (( ${#d} )) && { print -r -- ${d[1]}; return 0; }
  done
  return 1
}

# ipp_apk_signer <apk>: print the signer certificate SHA-256 (lower hex) of the first signer, or nothing.
ipp_apk_signer() {
  local as; as=$(ipp_apksigner) || return 1
  perl -e 'alarm shift; exec @ARGV' 60 $as verify --print-certs "$1" </dev/null 2>/dev/null \
    | sed -n 's/^Signer #1 certificate SHA-256 digest: *//p' | head -1 | tr 'A-F' 'a-f'
}
