#!/usr/bin/env bash
# Sign this plugin in. Runs under a pty, so a device code is printed and streamed
# to the admin page the instant the CLI emits it.
#
# **Two modes, and exactly one of them is in force.** `CLIMICROSOFT365_AUTHTYPE`
# picks it:
#
#   deviceCode   a person signs in and the server acts as that account
#   certificate  the app signs in as itself (app-only), nobody present
#
# One at a time is the whole design, not a limitation working around something.
# The CLI *can* hold several connections at once and switch between them, and
# that is precisely what would make this plugin unexplainable: a command's
# permissions would depend on which connection happened to be current, and the
# admin page's "authenticated" light would be answering about a connection nobody
# chose. So this script signs the old connection out before making a new one, and
# auth-status.sh reports the plugin signed in only while the stored connection's
# type matches the mode set here. Change the mode and the plugin reads as signed
# out until you authenticate again — which is the truth, for the mode you asked
# for.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_m365 || exit 1

mode="${CLIMICROSOFT365_AUTHTYPE:-deviceCode}"
case "$mode" in
  deviceCode | certificate) ;;
  *)
    echo "Unknown sign-in mode \"$mode\"." >&2
    echo "Set Plugins -> m365 -> Sign-in mode to 'deviceCode' or 'certificate'." >&2
    exit 2
    ;;
esac

# CLI for Microsoft 365 v10 removed its shared app registration, so every login
# needs an app (client) id — both modes. Without one the CLI *prompts* for it, and
# a prompt in a browser terminal is a bad way to supply a GUID, so refuse with the
# fix instead. `CLIMICROSOFT365_ENTRAAPPID` comes from the plugin's settings.
if [ -z "${CLIMICROSOFT365_ENTRAAPPID:-}" ]; then
  echo "No Entra app (client) ID is configured for this plugin." >&2
  echo >&2
  echo "Set it in the admin app: Plugins -> m365 -> Entra app (client) ID, then" >&2
  echo "run Authenticate again. It is the application (client) ID of the Entra app" >&2
  echo "registration this server signs in with." >&2
  exit 2
fi

# Never block on a prompt. Every value this login needs is passed explicitly
# below, so a prompt here can only mean something is misconfigured — and a
# session waiting on a question nobody can see is worse than a clear failure.
export CLIMICROSOFT365_PROMPT=false

# Where an opened certificate is written, when there is one. Inside the plugin's
# state folder (never listed by the API, never served by the file viewer) and
# removed however this script ends — the CLI copies the certificate into its own
# connection store at login, so nothing here needs to outlive the sign-in.
cert_workdir=""
cleanup() { [ -n "$cert_workdir" ] && rm -rf "$cert_workdir"; }
# INT and TERM as well as EXIT: a session the admin closes is killed, and an EXIT
# trap alone does not run for a signal that was never trapped — which would leave
# an opened private key behind. (SIGKILL cannot be caught at all, which is what
# the sweep in prepare_certificate is for.)
trap cleanup EXIT INT TERM

# Path handed to `--certificateFile`, produced by prepare_certificate.
cert_path=""

# Turn the configured certificate into one readable file holding the certificate
# and an *unencrypted* private key, and set `cert_path` to it.
#
# **The password is never an argument.** `/proc/<pid>/cmdline` is world-readable,
# so `--password "$secret"` publishes the secret to every account on the box. The
# CLI has no other way to take it — so instead of passing it on, this opens the
# certificate here (openssl reads the password from the *environment*, naming the
# variable rather than its value) and hands the CLI a copy that needs no password.
# That is also why openssl is a hard requirement for a protected certificate and
# not one otherwise.
#
# **One channel for the certificate, on purpose.** A "path to a file on the
# server" setting was written and then removed: it said exactly what the base64
# secret says, needed a guard for the two disagreeing, and only helped someone who
# already had shell access on this box — who can just run `base64 -w0` there.
prepare_certificate() {
  local source_path src

  if [ -z "${CLIMICROSOFT365_CERTIFICATE_BASE64:-}" ]; then
    echo "Certificate sign-in is selected, but no certificate is configured." >&2
    echo >&2
    echo "In the admin app, under Plugins -> m365 -> Certificate, base64-encoded, paste" >&2
    echo "the certificate AND its private key (a .pfx, or a .pem holding both):" >&2
    echo "    base64 -w0 cert.pfx" >&2
    echo >&2
    echo "Then add its password, if it has one, and run Authenticate again. The same" >&2
    echo "certificate's PUBLIC half must be uploaded to the app registration under" >&2
    echo "Certificates & secrets -> Certificates, or Entra will not know it." >&2
    return 2
  fi

  # 0077 so every file below is readable only by this user, including the
  # decrypted key. Set before the first write, not after.
  umask 077
  # Sweep anything an earlier run could not clean up after itself — a SIGKILL, a
  # server restart mid-login. Old opened keys are exactly what should not linger.
  rm -rf "${PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}"/m365-cert.* 2>/dev/null || true
  cert_workdir=$(mktemp -d "${PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}/m365-cert.XXXXXX") || {
    echo "Could not create a working directory for the certificate." >&2
    return 1
  }

  # `tr -d` first: a pasted base64 blob routinely arrives with newlines, and some
  # `base64` builds refuse them.
  if ! printf '%s' "$CLIMICROSOFT365_CERTIFICATE_BASE64" | tr -d '[:space:]' |
    base64 -d >"$cert_workdir/supplied" 2>/dev/null; then
    echo "The base64 certificate could not be decoded." >&2
    echo "It has to be the base64 of the certificate FILE — \`base64 -w0 cert.pfx\` —" >&2
    echo "not a thumbprint, not the PEM text on its own, and not a password." >&2
    return 2
  fi
  if [ ! -s "$cert_workdir/supplied" ]; then
    echo "The base64 certificate decoded to nothing." >&2
    return 2
  fi
  source_path="$cert_workdir/supplied"

  # No password: hand the file over as it is. A .pfx with no password and a .pem
  # with an unencrypted key are both things the CLI opens by itself.
  if [ -z "${CLIMICROSOFT365_CERTIFICATE_PASSWORD:-}" ]; then
    cert_path="$source_path"
    return 0
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    echo "This certificate has a password, and openssl is not on this server." >&2
    echo >&2
    echo "The password is deliberately never passed to the CLI on a command line —" >&2
    echo "process arguments are readable by every account on the box — so openssl is" >&2
    echo "what opens the certificate here instead. Either install it (apt-get install" >&2
    echo "openssl / dnf install openssl, then run the plugin's Install again), or" >&2
    echo "supply a certificate whose private key is not password-protected and clear" >&2
    echo "the password field." >&2
    return 1
  fi

  src="$source_path"
  local out="$cert_workdir/opened.pem" err="$cert_workdir/openssl.err"

  if head -c 64 "$src" 2>/dev/null | grep -q -- '-----BEGIN'; then
    # PEM with an encrypted key: decrypt the key, keep the certificate as it is,
    # and concatenate the two — which is the shape the CLI expects anyway.
    if ! openssl pkey -in "$src" -passin env:CLIMICROSOFT365_CERTIFICATE_PASSWORD \
      -out "$cert_workdir/key.pem" 2>"$err"; then
      echo "The private key in the PEM could not be opened with the configured password." >&2
      sed 's/^/  openssl: /' "$err" >&2
      return 2
    fi
    if ! openssl x509 -in "$src" -out "$cert_workdir/cert.pem" 2>"$err"; then
      echo "No certificate found in the PEM — it looks like a key on its own." >&2
      echo "The file has to hold the certificate AND its private key." >&2
      sed 's/^/  openssl: /' "$err" >&2
      return 2
    fi
    cat "$cert_workdir/key.pem" "$cert_workdir/cert.pem" >"$out"
  else
    # PKCS#12 (.pfx/.p12). `-legacy` on the retry because a .pfx exported from an
    # older Windows uses RC2, which OpenSSL 3 will not touch without it — a very
    # common file meeting a very common openssl, so it is worth the second try
    # rather than a failure the admin has to decode.
    if ! openssl pkcs12 -in "$src" -out "$out" -nodes \
      -passin env:CLIMICROSOFT365_CERTIFICATE_PASSWORD 2>"$err"; then
      if ! openssl pkcs12 -legacy -in "$src" -out "$out" -nodes \
        -passin env:CLIMICROSOFT365_CERTIFICATE_PASSWORD 2>"$err"; then
        echo "The certificate could not be opened with the configured password." >&2
        echo "Either the password is wrong, or the file is not a .pfx/.p12." >&2
        sed 's/^/  openssl: /' "$err" >&2
        return 2
      fi
    fi
  fi

  if [ ! -s "$out" ]; then
    echo "The certificate opened but produced nothing usable." >&2
    return 1
  fi
  cert_path="$out"
  return 0
}

echo "Signing in to Microsoft 365."
echo "Mode:            $mode"
echo "App (client) ID: $CLIMICROSOFT365_ENTRAAPPID"
[ -n "${CLIMICROSOFT365_TENANT:-}" ] && echo "Tenant:          $CLIMICROSOFT365_TENANT"
echo

args=(login --authType "$mode" --appId "$CLIMICROSOFT365_ENTRAAPPID")
[ -n "${CLIMICROSOFT365_TENANT:-}" ] && args+=(--tenant "$CLIMICROSOFT365_TENANT")

if [ "$mode" = certificate ]; then
  # Client credentials are issued by one tenant, for one tenant. `common` and
  # `organizations` are routing hints for a user sign-in and mean nothing without
  # a user — the token endpoint rejects them, with an error that does not say so.
  case "${CLIMICROSOFT365_TENANT:-}" in
    "" | common | organizations)
      echo "Certificate sign-in needs a real tenant, and Tenant is '${CLIMICROSOFT365_TENANT:-unset}'." >&2
      echo >&2
      echo "App-only sign-in has no user to route, so 'common' and 'organizations' are" >&2
      echo "not answers here. Put the directory (tenant) GUID in Plugins -> m365 ->" >&2
      echo "Tenant — it is on the app registration's overview blade — and run" >&2
      echo "Authenticate again." >&2
      exit 2
      ;;
  esac

  prepare_certificate || exit $?
  # No `--thumbprint`: the CLI computes it from the certificate itself, and a
  # certificate whose real thumbprint is not the one Entra has on record is a
  # broken registration rather than something a setting should paper over.
  args+=(--certificateFile "$cert_path")
  echo "Certificate opened. Signing in as the application — nothing to do here, this"
  echo "takes a few seconds."
else
  echo "Open the URL below, enter the code, and sign in with the account this server should use."
fi
echo

# Clear any existing connection first. Two reasons, and both bite: a stale one
# makes the CLI try a silent token refresh before it offers a device code, and a
# refresh token that is no longer valid fails the whole login with `invalid_grant`
# — no code, no explanation. And this is where one mode replaces another, so the
# connection the previous mode left behind has to go with it. Signing in is
# exactly the moment it is safe to drop the old one.
m365 logout >/dev/null 2>&1 || true

m365 "${args[@]}"
code=$?

echo
if [ "$code" -eq 0 ]; then
  echo "Signed in as:"
  m365 status --output text || true
  if [ "$mode" = certificate ]; then
    echo
    echo "This is an APP-ONLY sign-in: commands run as the application, with the"
    echo "application permissions granted to it — not as any person. If a command now"
    echo "fails with 'Insufficient privileges' or returns nothing where a user would"
    echo "see something, check the app registration's API permissions: it needs"
    echo "APPLICATION permissions (with admin consent), and delegated ones do nothing"
    echo "in this mode."
  fi
elif [ "$mode" = certificate ]; then
  echo "Sign-in did not complete (exit $code)." >&2
  echo >&2
  echo "What the common failures mean, read off the AADSTS code above:" >&2
  echo "  AADSTS700027 / 'Client assertion contains an invalid signature'" >&2
  echo "      Entra does not know this certificate for this app. The PUBLIC half has" >&2
  echo "      to be uploaded to the app registration (Certificates & secrets ->" >&2
  echo "      Certificates), and it must be the same certificate configured here." >&2
  echo "  AADSTS700016 / invalid_client" >&2
  echo "      The app (client) ID is wrong, or no such app exists in this tenant." >&2
  echo "  AADSTS90002 / 'Tenant not found'" >&2
  echo "      The Tenant setting is not a tenant this app lives in. Use the GUID." >&2
  echo "  AADSTS7000222 / 'The provided client secret keys are expired'" >&2
  echo "      The certificate has expired. Issue a new one, upload it to the app" >&2
  echo "      registration, and replace it here." >&2
else
  echo "Sign-in did not complete (exit $code)." >&2
  echo >&2
  echo "What the common failures mean, read off the AADSTS code above:" >&2
  echo "  AADSTS7000014  (invalid_grant, \"device_code is not valid\")" >&2
  echo "      Almost always the wrong Tenant. A single-tenant app registration" >&2
  echo "      cannot authenticate through 'common' — put your tenant's GUID in the" >&2
  echo "      plugin's Tenant setting and try again. This one shows no code at all," >&2
  echo "      which is how you tell it apart from a code that went unused." >&2
  echo "  AADSTS700016 / invalid_client" >&2
  echo "      The app (client) ID is wrong, or no such app exists in this tenant." >&2
  echo "  AADSTS7000218" >&2
  echo "      The app registration is not a public client. Turn on 'Allow public" >&2
  echo "      client flows', which is what device-code sign-in requires." >&2
  echo "  AADSTS70016 / expired_token" >&2
  echo "      The code was not entered in time. Run Authenticate again." >&2
fi
exit "$code"
