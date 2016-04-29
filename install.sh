#!/bin/bash

# TODO
# pull exit numbers into variables
# check prereq binaries
# use bash if conds everywhere

# we call run() at the end of the script to prevent inconsistent state in case
# curl|bash fails in the middle of the download
# (https://www.seancassidy.me/dont-pipe-to-your-shell.html)
run() {
  set -euo pipefail
  IFS=$'\n'

  VERSION="v0.1.1"
  GITHUB_URL="https://github.com/thoughtworks/talisman"
  BINARY_URL="$GITHUB_URL/releases/download/$VERSION/talisman"
  EXPECTED_BINARY_SHA="fdfa31d22e5acaef3ca2f57b1036f4c2f3b9601b00524c753a5919a6c8fa3cd3"
  REPO_PRE_PUSH_HOOK=".git/hooks/pre-push"
  DOWNLOADED_BINARY=""
  DEFAULT_GLOBAL_TEMPLATE_DIR="$HOME/.git-templates"
  
  echo_error() {
    echo -ne $(tput setaf 1)
    echo "$1" >&2
    echo -ne $(tput setaf 9)
  }

  function binary_arch_suffix() {
    declare ARCHITECTURE
    if [ "$(uname -s)" = "Linux" ]; then
      ARCHITECTURE="linux"
    elif [ "$(uname -s)" = "Darwin"]; then
      ARCHITECTURE="darwin"
    else
      echo_error "Talisman currently only supports Linux and Darwin systems"
      echo_error "If this is a problem for you, please open an issue: https://github.com/thoughtworks/talisman/issues/new"
      exit 7
    fi

    if [[ "$(uname -m)" = "x86_64" ]]; then
      ARCHITECTURE="${ARCHITECTURE}_amd64"
    elif [[ "$(uname -m)" =~ '^i.?86$' ]]; then
      ARCHITECTURE="${ARCHITECTURE}_386"
    else
      echo_error "Talisman currently only supports x86 and x86_64 architectures"
      echo_error "If this is a problem for you, please open an issue: https://github.com/thoughtworks/talisman/issues/new"
      exit 8
    fi
    
    echo $ARCHITECTURE
  }


  download_and_verify() {
    echo 'Downloading and verifying binary...'
    echo
    
    TMP_DIR=$(mktemp -d)
    trap 'rm -r $TMP_DIR' EXIT
    chmod 0700 $TMP_DIR

    curl --location --silent "${BINARY_URL}_$(binary_arch_suffix)" > $TMP_DIR/talisman

    DOWNLOAD_SHA=$(shasum -b -a256 $TMP_DIR/talisman | cut -d' ' -f1)

    if [ ! "$DOWNLOAD_SHA" = "$EXPECTED_BINARY_SHA" ]; then
      echo_error "Uh oh... SHA256 checksum did not verify. Binary download must have been corrupted in some way."
      echo_error "Expected SHA: $EXPECTED_BINARY_SHA"
      echo_error "Download SHA: $DOWNLOAD_SHA"
      exit 3
    fi

    DOWNLOADED_BINARY="$TMP_DIR/talisman"
  }

  install_to_repo() {
    if [ -x "$REPO_PRE_PUSH_HOOK" ]; then
      echo_error "Oops, it looks like you already have a pre-push hook installed at '$REPO_PRE_PUSH_HOOK'."
      echo_error "Talisman is not compatible with other hooks right now, sorry."
      echo_error "If this is a problem for you, please open an issue: https://github.com/thoughtworks/talisman/issues/new"
      exit 2
    fi

    download_and_verify

    cp $DOWNLOADED_BINARY $REPO_PRE_PUSH_HOOK
    chmod +x $REPO_PRE_PUSH_HOOK

    echo -ne "\e[32m"
    echo "Talisman successfully installed to '$REPO_PRE_PUSH_HOOK'"
    echo -ne "\e[0m"
  }

  install_to_git_templates() {
    if [ ! -t 1 ]; then
      echo_error "Headless install to system templates is not supported."
      echo_error "If you would like this feature, please open an issue: https://github.com/thoughtworks/talisman/issues/new"
      exit 6
    fi

    TEMPLATE_DIR=$(git config --global init.templatedir) || true

    echo "Not running from inside a git repository... installing as a"
    echo "git template."
    echo
    echo "If you meant to install to a specific repo, 'cd' into that"
    echo "repo and run this script again."
    echo
    echo "Installing as a template will automatically add Talisman to"
    echo "any new repo that you 'init' or 'clone'."
    echo

    if [ "$TEMPLATE_DIR" = "" ]; then
      echo "No git template directory is configured. Let's add one."
      echo "(this will override any system git templates and modify your git config file)"
      echo
      read -u1 -p "Git template directory: ($DEFAULT_GLOBAL_TEMPLATE_DIR) " TEMPLATE_DIR
      echo
      TEMPLATE_DIR=${TEMPLATE_DIR:-$DEFAULT_GLOBAL_TEMPLATE_DIR}
      git config --global init.templatedir $TEMPLATE_DIR
    else
      echo "You already have a git template directory configured."
      echo
      read -u1 -p "Add Talisman to '$TEMPLATE_DIR/hooks?' (Y/n) " USE_EXISTING
      echo
      
      if [ "$USE_EXISTING" != "Y" ] && [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "" ]; then
	echo_error "Not installing Talisman."
	echo_error "If you were trying to install into a single git repo, re-run this command from that repo."
	echo_error "You can always download/compile manually from our Github page: $GITHUB_URL"
	exit 4
      fi
    fi

    # Support '~' in path
    TEMPLATE_DIR=${TEMPLATE_DIR/#\~/$HOME}

    if [ -f "$TEMPLATE_DIR/hooks/pre-push" ]; then
      echo_error "Oops, it looks like you already have a pre-push hook installed at '$TEMPLATE_DIR/hooks/pre-push'."
      echo_error "Talisman is not compatible with other hooks right now, sorry."
      echo_error "If this is a problem for you, please open an issue: https://github.com/thoughtworks/talisman/issues/new"
      exit 5
    fi
    
    mkdir -p "$TEMPLATE_DIR/hooks"

    download_and_verify

    cp $DOWNLOADED_BINARY "$TEMPLATE_DIR/hooks/pre-push"
    chmod +x "$TEMPLATE_DIR/hooks/pre-push"
    
    echo -ne $(tput setaf 2)
    echo "Talisman successfully installed"
    echo -ne $(tput setaf 9)
  }

  if [ ! -d "./.git" ]; then
    install_to_git_templates
  else
    install_to_repo
  fi
}

run $0 $@
