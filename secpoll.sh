#!/bin/sh
set -e

die() {
  echo "::error ::$1"
  echo "::error ::This is a fatal error ... asking Action Host to kill our workflow"
  curl -s \
    -X POST \
    -H "$AUTHORIZATION_HEADER" \
    -H "Accept: application/vnd.github.v3+json" \
    "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/cancel" >/dev/null
  for i in $(seq 2); do
    sleep 1
  done
  exit 200
}

dns_server() {
  if [ -n "$INPUT_ANONYMIZE_SECPOLL_SOURCE" ]; then
    perl -e '
    my @dns_servers=qw(1.1.1.1 8.8.8.8 9.9.9.9);
    my $index=rand(scalar @dns_servers);
    print "@".$dns_servers[$index];'
  fi
}

base_domain=check-spelling.dev
version=$(cat "$spellchecker/version")
version_reversed=$(echo $version|tr '.' "\n" | tac| tr "\n" '.')
poll_status=$(dig txt +noauthority +answer +noquestion ${version_reversed}security-status.secpoll.${base_domain} $(dns_server) 2>&1 |
perl -e 'while (<>) {
  if (/command not found/) {
    $poll_status = $_;
  } elsif (/^;; ->>HEADER<<- opcode: QUERY, status: (\w+),/) {
    $poll_status = $1;
  } elsif (/^[^;].*"(.*)"$/) {
    $poll_status = $1;
  }
}
print "$poll_status\n";')

expect_empty_advisory() {
  if [ -n "$INPUT_IGNORE_SECURITY_ADVISORY" ]; then
    die "Invalid configuration. ignore_security_advisory was set to '$INPUT_IGNORE_SECURITY_ADVISORY' but there is no security advisory for version $version"
  fi
}

case "$poll_status" in
  *"command not found")
    echo "::warning ::couldn't perform dns lookup: '$poll_status'" >&2
  ;;
  "")
    expect_empty_advisory
  ;;
  "1 "*)
    poll_status=${poll_status#1 }
    expect_empty_advisory
    echo "Found ok status for version $version: '$poll_status'"
  ;;
  NXDOMAIN)
    expect_empty_advisory
  ;;
  "3 "*)
    poll_status=${poll_status#3 }
    if [ -z "$INPUT_IGNORE_SECURITY_ADVISORY" ]; then
      die "Found security advisory for version $version: '$poll_status'"
    fi
    if [ "$poll_status" != "$INPUT_IGNORE_SECURITY_ADVISORY" ]; then
      die "Found security advisory for version $version: '$poll_status' (ignore_security_advisory did not match)"
    fi
    echo "::warning ::Ignoring security advisory '$INPUT_IGNORE_SECURITY_ADVISORY' for version $version -- this is not recommended" >&2
  ;;
  "2 "*)
    poll_status=${poll_status#2 }
    echo "::warning ::Found note for version $version: '$poll_status'" >&2
  ;;
esac
