#!/usr/bin/zsh

# Prompt environment helpers

_zaic_os_description() {
  local os="${ZSH_AI_COMMANDS_OS:-auto}"

  if [[ "$os" == auto ]]; then
    case "$(uname -s 2>/dev/null)" in
      Darwin) os=macos ;;
      Linux)  os=linux ;;
      *)      os="$(uname -s 2>/dev/null || print unknown)" ;;
    esac
  fi

  case "${os:l}" in
    macos|darwin)
      print -r -- "zsh on macOS (Darwin). Prefer BSD/macOS-compatible commands unless GNU tools are explicitly requested."
      ;;
    linux|ubuntu)
      print -r -- "zsh on Linux (Ubuntu/Debian-like). Prefer GNU coreutils and Linux tools."
      ;;
    *)
      print -r -- "zsh on ${os}."
      ;;
  esac
}

_zaic_available_commands() {
  local -a candidates available
  candidates=(rg jq fzf fd sed awk perl curl git find xargs du sort grep ss lsof ps kill pkill systemctl journalctl apt apt-get)

  local cmd
  for cmd in "${candidates[@]}"; do
    (( $+commands[$cmd] )) && available+=("$cmd")
  done

  print -r -- "${(j:, :)available}"
}

_zaic_system_prompt() {
  local os_description available_commands extra_environment
  os_description="$(_zaic_os_description)"
  available_commands="$(_zaic_available_commands)"
  extra_environment="${ZSH_AI_COMMANDS_ENVIRONMENT:-}"

  cat <<PROMPT
You are an expert sysadmin and shell scripter. Given a task description, output a single shell one-liner.

Environment:
- Shell: ${os_description}
- Available beyond the shell defaults: ${available_commands:-unknown}.
${extra_environment:+- Additional user-provided environment notes: ${extra_environment}
}
Output rules:
- Print ONLY the bare command. Nothing else.
- No markdown, no code fences, no backticks, no commentary, no leading/trailing whitespace.
- The command must be a single logical line. Use pipes, &&, ||, ;, or subshells to chain steps. Never use literal newlines.
- Quoting: prefer single quotes for fixed strings, double quotes when variable expansion or escapes are needed. Escape carefully inside nested quotes.
- Prefer sensible defaults, but when you can't, use <placeholder> for values that must be filled in, e.g. <file>, <pattern>, <port>.
- If you must include commentary, wrap the command in a \`\`\` block so it can be extracted.

Command quality:
- Prefer simple, robust solutions. Avoid unnecessary subshells or processes.
- Prefer commands that are native to the detected OS and installed tools.
- When the task is ambiguous, pick the most common interpretation rather than asking for clarification.
PROMPT
}
