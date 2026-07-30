#!/usr/bin/env zsh
# prompt-segments - the segments z1's own prompt is built from.
#
#   source /path/to/lib/prompt.zsh
#   source /path/to/lib/prompt-segments.zsh
#   zstyle ':z1:prompt' format '$pwd $char '
#   z1-prompt-build
#
# Sourcing this registers the segments below and nothing else, so a prompt of
# your own can take the ones it wants and leave the rest. Sourcing it again is
# harmless, and re-reads the styles, which is how a prompt re-themes itself.
#
#   pwd     the working directory, last component picked out
#   git     the branch and what is going on in the worktree
#   char    the prompt character, colored by the last exit status
#   status  that exit status, when it was not zero
#   timer   how long the last command took, when it took a while
#
# Each is configured under ':z1:prompt:segment:<name>'. See lib/prompt.zsh for
# what every segment understands (async, disabled) and for how a format string
# puts them together.

(( $+functions[z1-prompt-segment] )) || {
  print -ru2 "prompt-segments: lib/prompt.zsh has to be sourced first"
  return 1
}

zmodload zsh/datetime

# vcs_info's formats are built out of colors, so the palette has to be resolved
# before this file gets to them. Doing it here rather than leaving it to
# z1-prompt-build keeps the order from mattering to whoever sources this.
z1-prompt-palette

#
# Characters
#
# Each is a style away from being something else:
#   zstyle ':z1:prompt:character' dirty '*'
#   zstyle ':z1:prompt' ascii 'yes'
#

z1-prompt-character success '❯' '%%'
z1-prompt-character error   '❯' '%%'
z1-prompt-character vicmd   '❮' 'V'
z1-prompt-character stash   '☰' '='
z1-prompt-character dirty   '•' '*'
z1-prompt-character ahead   '⇡' '+'
z1-prompt-character behind  '⇣' '-'

#
# pwd
#

# How much of the path to show:
#   zstyle ':z1:prompt' pwd-length 'full'   # $PWD as it is
#   zstyle ':z1:prompt' pwd-length 'long'   # the same, with ~ for $HOME
#   (anything else)                         # one letter per parent directory
#
# The last component is picked out from the rest, since that is the part anyone
# is actually reading. $z1_prompt_pwd holds the path before it was colored.
typeset -g z1_prompt_pwd=

function z1-prompt-segment-pwd() {
  setopt local_options extended_glob

  local cur_pwd="${PWD/#$HOME/~}"
  local MATCH head tail

  if [[ "$cur_pwd" == (#m)[/~] ]]; then
    z1_prompt_pwd="$MATCH"
  elif zstyle -m ':z1:prompt' pwd-length 'full'; then
    z1_prompt_pwd=${PWD}
  elif zstyle -m ':z1:prompt' pwd-length 'long'; then
    z1_prompt_pwd=${cur_pwd}
  else
    z1_prompt_pwd="${${${${(@j:/:M)${(@s:/:)cur_pwd}##.#?}:h}%/}//\%/%%}/${${cur_pwd:t}//\%/%%}"
  fi

  if [[ "$z1_prompt_pwd" == */* ]]; then
    head="${z1_prompt_pwd%/*}/"
    tail="${z1_prompt_pwd##*/}"
  else
    head=''
    tail="$z1_prompt_pwd"
  fi

  REPLY="$z1_prompt_fg[blue]$head%f%B$z1_prompt_fg[cyan]$tail%f%b"
}
z1-prompt-segment pwd z1-prompt-segment-pwd

#
# git
#

autoload -Uz vcs_info

# Fill in %m with how far ahead or behind the upstream is, and notice the
# untracked files and updated submodules that vcs_info does not.
function +vi-git_status() {
  if [[ -n $(git ls-files --other --exclude-standard 2> /dev/null) ]]; then
    hook_com[unstaged]="$z1_prompt_fg[red]$z1_prompt_char[dirty]%f"
  fi

  local -a gitstatus

  # Cleared first: the git backend fills misc with rebase patch state, and the
  # action in actionformats already says a rebase is underway.
  hook_com[misc]=''

  # Nothing to be ahead or behind of on a detached HEAD.
  git rev-parse ${hook_com[branch]}@{upstream} >/dev/null 2>&1 || return 0

  local -a ahead_and_behind=(
    $(git rev-list --left-right --count HEAD...${hook_com[branch]}@{upstream} 2>/dev/null)
  )

  (( ${ahead_and_behind[1]} )) && gitstatus+=( "$z1_prompt_char[ahead]${ahead_and_behind[1]}" )
  (( ${ahead_and_behind[2]} )) && gitstatus+=( "$z1_prompt_char[behind]${ahead_and_behind[2]}" )

  hook_com[misc]=${(j:/:)gitstatus}
}

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr "$z1_prompt_fg[green]$z1_prompt_char[dirty]%f"
zstyle ':vcs_info:*' unstagedstr "$z1_prompt_fg[yellow]$z1_prompt_char[dirty]%f"
zstyle ':vcs_info:*' formats "$z1_prompt_fg[magenta]%b%f%c%u%m"
zstyle ':vcs_info:*' actionformats \
  "$z1_prompt_fg[magenta]%b%f%c%u%m|$z1_prompt_fg[cyan]%a%f"
zstyle ':vcs_info:git*+set-message:*' hooks git_status

function z1-prompt-segment-git() {
  vcs_info
  REPLY=$vcs_info_msg_0_
}
z1-prompt-segment git z1-prompt-segment-git

# vcs_info costs tens of milliseconds, which is worth keeping off the critical
# path when lib/async.zsh is around. Say so only when nobody else has, so this
# stays a default rather than an override.
() {
  local -a set
  zstyle -g set ':z1:prompt:segment:git' async \
    || zstyle ':z1:prompt:segment:git' async 'yes'
}

#
# char
#

# The keymap picks the character and the exit status picks the color, both read
# every time zsh draws the prompt rather than once per command, so vi command
# mode shows up the moment you switch into it. That is what -s is for.
function z1-prompt-segment-char() {
  REPLY="%(?.$z1_prompt_fg[green].$z1_prompt_fg[red])"
  REPLY+='${z1_prompt_char[${KEYMAP:-main}]'
  REPLY+=":-%(?.\$z1_prompt_char[success].\$z1_prompt_char[error])}%f"
}
z1-prompt-segment -s char z1-prompt-segment-char

#
# status
#

# Nothing at all after a command that worked, so this needs no group around it.
function z1-prompt-segment-status() {
  REPLY="%(?..$z1_prompt_fg[red]%?%f)"
}
z1-prompt-segment -s status z1-prompt-segment-status

#
# timer
#

# How long the last command ran, once it runs long enough to be worth saying:
#   zstyle ':z1:prompt:segment:timer' threshold '5'
# The hooks are always installed, since knowing when a command started means
# being there when it starts. They cost two assignments.
typeset -gF z1_prompt_timer_elapsed=0
typeset -gF _z1_prompt_timer_start=0

function z1-prompt-timer-preexec() { _z1_prompt_timer_start=$EPOCHREALTIME }

function z1-prompt-timer-precmd() {
  if (( _z1_prompt_timer_start > 0 )); then
    (( z1_prompt_timer_elapsed = EPOCHREALTIME - _z1_prompt_timer_start ))
    _z1_prompt_timer_start=0
  else
    z1_prompt_timer_elapsed=0
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec z1-prompt-timer-preexec
# Ahead of the render hook, so the segment reads this command's time and not the
# one before it.
add-zsh-hook precmd z1-prompt-timer-precmd
precmd_functions=(
  z1-prompt-timer-precmd ${precmd_functions:#z1-prompt-timer-precmd}
)

function z1-prompt-segment-timer() {
  REPLY=
  local threshold
  zstyle -s ':z1:prompt:segment:timer' threshold threshold || threshold=5
  (( z1_prompt_timer_elapsed >= threshold )) || return 0

  local -F t=$z1_prompt_timer_elapsed
  local -i h=$(( t / 3600 )) m=$(( (t / 60) % 60 )) s=$(( t % 60 ))

  if (( h )); then
    REPLY="${h}h${m}m${s}s"
  elif (( m )); then
    REPLY="${m}m${s}s"
  else
    printf -v REPLY '%.1fs' $t
  fi

  REPLY="$z1_prompt_fg[yellow]$REPLY%f"
}
z1-prompt-segment timer z1-prompt-segment-timer
