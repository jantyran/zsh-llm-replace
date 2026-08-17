#!/usr/bin/zsh
# Unit tests for prompt environment helpers

local _old_os="${ZSH_AI_COMMANDS_OS-}"
local _old_env="${ZSH_AI_COMMANDS_ENVIRONMENT-}"
local _had_os=0 _had_env=0
(( ${+ZSH_AI_COMMANDS_OS} )) && _had_os=1
(( ${+ZSH_AI_COMMANDS_ENVIRONMENT} )) && _had_env=1

typeset -g ZSH_AI_COMMANDS_OS=linux
assert_eq "environment: linux target" \
  "zsh on Linux (Ubuntu/Debian-like). Prefer GNU coreutils and Linux tools." \
  "$(_zaic_os_description)"

typeset -g ZSH_AI_COMMANDS_OS=macos
assert_eq "environment: macos target" \
  "zsh on macOS (Darwin). Prefer BSD/macOS-compatible commands unless GNU tools are explicitly requested." \
  "$(_zaic_os_description)"

typeset -g ZSH_AI_COMMANDS_OS=linux
typeset -g ZSH_AI_COMMANDS_ENVIRONMENT="Docker is available; prefer apt-get for package installs."
local _prompt="$(_zaic_system_prompt)"
assert_eq "environment: prompt includes linux" \
  1 \
  "$([[ "$_prompt" == *"zsh on Linux"* ]] && print 1 || print 0)"
assert_eq "environment: prompt includes user notes" \
  1 \
  "$([[ "$_prompt" == *"Docker is available"* ]] && print 1 || print 0)"

if (( _had_os )); then
  typeset -g ZSH_AI_COMMANDS_OS="$_old_os"
else
  unset ZSH_AI_COMMANDS_OS
fi

if (( _had_env )); then
  typeset -g ZSH_AI_COMMANDS_ENVIRONMENT="$_old_env"
else
  unset ZSH_AI_COMMANDS_ENVIRONMENT
fi
