#!/usr/bin/env bats
# Prompts are made available to zsh's own prompt system through fpath. Starting
# that system is left to the user, so these tests run promptinit themselves.
#
# The bundled prompt is now composed: lib/prompt.zsh is the engine,
# lib/prompt-segments.zsh has the segments, and prompt_z1_setup picks a format
# and adds the transient behavior. These check the prompt as a user meets it;
# tests/bats/prompt_engine.bats checks the engine on its own.

load helpers/common

setup() { z1_setup; }
teardown() { z1_teardown; }

@test "the bundled z1 prompt is on fpath" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit
    print -l $prompt_themes | grep -qx z1 && print "z1: listed" || print "z1: missing"'
  assert_success
  assert_line "z1: listed"
}

@test "the bundled prompt actually loads" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit
    prompt z1
    print "rc: $?"
    print "precmd: $(( $precmd_functions[(I)prompt_z1_precmd] > 0 ))"
    print "render: $(( $precmd_functions[(I)z1-prompt-render] > 0 ))"
    [[ -n "$PROMPT" ]] && print "prompt: set" || print "prompt: empty"'
  assert_success
  assert_line "rc: 0"
  assert_line "precmd: 1"
  assert_line "render: 1"
  assert_line "prompt: set"
}

@test "your own prompts directory is picked up" {
  write_file "$TEST_HOME/.config/zsh/prompts/prompt_mine_setup" \
    'function prompt_mine_setup { PROMPT="mine> " }' \
    'prompt_mine_setup "$@"'

  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit
    print -l $prompt_themes | grep -qx mine && print "mine: listed" || print "mine: missing"'
  assert_success
  assert_line "mine: listed"
}

# Your prompts come first, so a prompt of your own with the same name as one z1
# ships wins.
@test "your prompts directory wins over the bundled one" {
  write_file "$TEST_HOME/.config/zsh/prompts/prompt_z1_setup" \
    'function prompt_z1_setup { PROMPT="overridden> " }' \
    'prompt_z1_setup "$@"'

  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit
    prompt z1
    print "PROMPT: $PROMPT"'
  assert_success
  assert_line "PROMPT: overridden> "
}

# $ZDOTDIR has no prompts directory here, so only z1's own is added.
@test "only prompt directories that exist are added" {
  z1_zsh 'source $Z1
    print "missing: $(print -l $fpath | grep -c "prompts")"'
  assert_success
  assert_line "missing: 1"
}

@test "a copy of z1.zsh with no prompts directory still loads" {
  cp "$PRJDIR/z1.zsh" "$TEST_HOME/solo.zsh"

  z1_zsh 'source $HOME/solo.zsh
    print "rc: $?"
    print "prompts in fpath: $(print -l $fpath | grep -c "prompts")"'
  assert_success
  assert_line "rc: 0"
  assert_line "prompts in fpath: 0"
}

#
# Shape
#

# The whole point of the revamp: the prompt is a format string, so it can be
# rearranged without touching the theme.
@test "the format style rearranges the prompt" {
  z1_zsh 'zstyle ":z1:prompt" format "[\$pwd]"
    zstyle ":z1:prompt" right-format ""
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME
    z1-prompt-render
    print "rendered: [${(V)$(print -Pn -- $PROMPT)}]"
    print "rprompt: [$RPROMPT]"'
  assert_success
  assert_line "rendered: [[^[[38;5;39m^[[39m^[[1m^[[38;5;37m~^[[39m^[[0m]]"
  assert_line "rprompt: []"
}

@test "the default shape is the path, the character, and git on the right" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    print "format: $z1_prompt_format"
    print "right: $z1_prompt_right_format"'
  assert_success
  assert_line 'format: $pwd $char '
  assert_line 'right: $git'
}

@test "a segment of your own drops into the format" {
  z1_zsh 'zstyle ":z1:prompt" format "\$pwd \$mine \$char "
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    function my-segment { REPLY="<mine>" }
    z1-prompt-segment mine my-segment
    z1-prompt-build
    print -Pn -- $PROMPT | grep -q "<mine>" && print "mine: shown" || print "mine: missing"'
  assert_success
  assert_line "mine: shown"
}

#
# Prompt character
#
# The character comes from $KEYMAP and the color from $?, both resolved while
# zsh draws rather than once per command. These render the char segment on its
# own, so the assertions do not move when the rest of the prompt changes.
# Characters are set explicitly so they do not move when the defaults change.
#
setup_chars() {
  echo 'zstyle ":z1:prompt:character" success S
    zstyle ":z1:prompt:character" error E
    zstyle ":z1:prompt:character" vicmd V
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    render() { KEYMAP=$2; ( exit $1 ); local o=$(print -Pn -- $z1_prompt_frag[char]); print -r -- "${(V)o}" }'
}

@test "vi command mode gets its own prompt character" {
  z1_zsh "$(setup_chars)"'
    print "main:  $(render 0 main)"
    print "viins: $(render 0 viins)"
    print "vicmd: $(render 0 vicmd)"'
  assert_success
  assert_line "main:  ^[[38;5;76mS^[[39m"
  assert_line "viins: ^[[38;5;76mS^[[39m"
  assert_line "vicmd: ^[[38;5;76mV^[[39m"
}

# zle also reports isearch and listscroll. Looking the keymap up in the
# character table means an unnamed one falls back rather than printing itself.
@test "an unrecognized keymap falls back to the success character" {
  z1_zsh "$(setup_chars)"'
    for k in isearch listscroll nonsense ""; do print "[$k] $(render 0 $k)"; done'
  assert_success
  assert_line "[isearch] ^[[38;5;76mS^[[39m"
  assert_line "[listscroll] ^[[38;5;76mS^[[39m"
  assert_line "[nonsense] ^[[38;5;76mS^[[39m"
  assert_line "[] ^[[38;5;76mS^[[39m"
}

@test "a failed command switches to the error character in red" {
  z1_zsh "$(setup_chars)"'
    print "ok:   $(render 0 main)"
    print "fail: $(render 1 main)"'
  assert_success
  assert_line "ok:   ^[[38;5;76mS^[[39m"
  assert_line "fail: ^[[38;5;160mE^[[39m"
}

# In command mode the keymap still owns the character, but the color follows the
# exit status, so a failure is not hidden by being in vi command mode.
@test "vi command mode keeps its character but takes the error color" {
  z1_zsh "$(setup_chars)"'
    print "ok:   $(render 0 vicmd)"
    print "fail: $(render 1 vicmd)"'
  assert_success
  assert_line "ok:   ^[[38;5;76mV^[[39m"
  assert_line "fail: ^[[38;5;160mV^[[39m"
}

@test "the palette styles are honored" {
  z1_zsh "$(setup_chars)"'
    zstyle ":z1:prompt:palette" red 196
    zstyle ":z1:prompt:palette" green 046
    prompt z1
    print "ok:   $(render 0 main)"
    print "fail: $(render 1 main)"'
  assert_success
  assert_line "ok:   ^[[38;5;46mS^[[39m"
  assert_line "fail: ^[[38;5;196mE^[[39m"
}

@test "asking for ascii gives ASCII characters" {
  z1_zsh 'zstyle ":z1:prompt" ascii yes
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    render() { KEYMAP=$1; local o=$(print -Pn -- $z1_prompt_frag[char]); print -r -- "${(V)o}" }
    print "ok:    $(render main)"
    print "vicmd: $(render vicmd)"'
  assert_success
  assert_line "ok:    ^[[38;5;76m%^[[39m"
  assert_line "vicmd: ^[[38;5;76mV^[[39m"
}

# prompt_z1_preview used to call editor-info, a prezto function z1 does not have.
@test "previewing the prompt does not call a missing function" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit
    print "$functions[prompt_z1_preview]" | grep -q editor-info && print "leftover: yes" || print "leftover: no"'
  assert_success
  assert_line "leftover: no"
}

#
# git
#

@test "the prompt runs vcs_info asynchronously when lib/async.zsh is there" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    print "async: $(( $+functions[async-task] ))"
    print "rprompt: $RPROMPT"
    print "task: ${async_tasks[z1-prompt-git]}"'
  assert_success
  assert_line "async: 1"
  assert_line 'rprompt: ${async_output[z1-prompt-git]}'
  assert_line "task: z1-prompt-async-git"
}

# The prompt has to work without lib/async.zsh, which is optional. lib/prompt.zsh
# and its segments are not, so a copy has to bring those along.
@test "the prompt falls back to synchronous vcs_info without the library" {
  mkdir -p "$TEST_HOME/solo/prompts" "$TEST_HOME/solo/lib"
  cp "$PRJDIR/z1.zsh" "$TEST_HOME/solo/z1.zsh"
  cp "$PRJDIR/prompts/prompt_z1_setup" "$TEST_HOME/solo/prompts/"
  cp "$PRJDIR/lib/prompt.zsh" "$PRJDIR/lib/prompt-segments.zsh" "$TEST_HOME/solo/lib/"

  z1_zsh 'source $HOME/solo/z1.zsh
    autoload -Uz promptinit && promptinit && prompt z1
    print "async: $(( $+functions[async-task] ))"
    print "rprompt: $RPROMPT"'
  assert_success
  assert_line "async: 0"
  assert_line 'rprompt: ${z1_prompt_frag[git]}'
}

# Asking for a segment in the background and then running it inline as well
# would be paying twice for the same thing.
@test "render does not run the git segment when the async task has it" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    vcs_info_msg_0_=untouched
    z1-prompt-render
    print "sync ran: $([[ $vcs_info_msg_0_ == untouched ]] && print no || print yes)"'
  assert_success
  assert_line "sync ran: no"
}

make_repo() {
  local r="$TEST_HOME/repo"
  git -C "$TEST_HOME" init -q repo
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name tester
  : >"$r/file"
  git -C "$r" add file
  git -C "$r" commit -qm init
}

@test "the async task produces the branch name in a repo" {
  make_repo

  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME/repo
    async-run; async-wait
    print "vcs: ${async_output[z1-prompt-git]}"'
  assert_success
  assert_output_contains "vcs: "
  refute_line "vcs: "
}

@test "the branch name is magenta" {
  make_repo

  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME/repo
    async-run; async-wait
    o=$(print -Pn -- $RPROMPT); print "branch: ${(V)o}"'
  assert_success
  assert_output_contains "branch: ^[[38;5;168m"
}

# vcs_info's git backend fills %m with rebase patch state, including a raw sha.
# The hook clears it, since actionformats already names the action.
@test "a rebase does not leak patch state into the prompt" {
  local r="$TEST_HOME/repo"
  git -C "$TEST_HOME" init -q repo
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name tester
  echo one >"$r/f"; git -C "$r" add f; git -C "$r" commit -qm one
  git -C "$r" checkout -q -b side
  echo side >"$r/f"; git -C "$r" commit -qam side
  git -C "$r" checkout -q -
  echo main >"$r/f"; git -C "$r" commit -qam main
  git -C "$r" rebase side >/dev/null 2>&1 || true

  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME/repo
    async-run; async-wait
    print "rprompt: ${(V)$(print -Pn -- $RPROMPT)}"'
  assert_success
  assert_output_contains "rebase"
  refute_output_matches "applied"
  refute_output_matches "[0-9a-f]{40}"
}

@test "the dirty marker uses the palette red, not basic red" {
  make_repo
  : >"$TEST_HOME/repo/untracked"

  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME/repo
    async-run; async-wait
    print "rprompt: ${(V)$(print -Pn -- $RPROMPT)}"'
  assert_success
  assert_output_contains "^[[38;5;160m"
  refute_output_matches '\^\[\[31m'
}

# The ahead and behind markers have their own styles, so they have to come from
# the character table rather than being written into the hook.
@test "the ahead marker comes from the character table" {
  make_repo
  git -C "$TEST_HOME" clone -q "$TEST_HOME/repo" clone
  git -C "$TEST_HOME/clone" config user.email t@example.com
  git -C "$TEST_HOME/clone" config user.name tester
  echo more >"$TEST_HOME/clone/file"
  git -C "$TEST_HOME/clone" commit -qam more

  z1_zsh 'zstyle ":z1:prompt:character" ahead "A"
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME/clone
    async-run; async-wait
    print "rprompt: ${async_output[z1-prompt-git]}"'
  assert_success
  assert_output_contains "A1"
}

#
# pwd
#

# The last path component is picked out from the rest: leading part blue, final
# component bold and cyan. $z1_prompt_pwd is the path before it was colored.
@test "the last path component is bold cyan and the rest blue" {
  mkdir -p "$TEST_HOME/one/two/three"

  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME/one/two/three
    z1-prompt-render
    print "pwd: [$z1_prompt_pwd]"
    o=$(print -Pn -- $PROMPT); print "rendered: ${(V)o}"'
  assert_success
  assert_line "pwd: [~/o/t/three]"
  assert_output_contains "^[[38;5;39m~/o/t/^[[39m^[[1m^[[38;5;37mthree^[[39m^[[0m"
}

@test "home is a single bold cyan component" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME
    z1-prompt-render
    print "pwd: [$z1_prompt_pwd]"
    o=$(print -Pn -- $PROMPT); print "rendered: ${(V)o}"'
  assert_success
  assert_line "pwd: [~]"
  assert_output_contains "^[[1m^[[38;5;37m~^[[39m^[[0m"
}

@test "root keeps its slash" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd /
    z1-prompt-render
    print "pwd: [$z1_prompt_pwd]"'
  assert_success
  assert_line "pwd: [/]"
}

@test "the pwd-length style shows the whole path" {
  mkdir -p "$TEST_HOME/one/two/three"

  z1_zsh 'zstyle ":z1:prompt" pwd-length long
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    builtin cd $HOME/one/two/three
    z1-prompt-render
    print "pwd: [$z1_prompt_pwd]"'
  assert_success
  assert_line "pwd: [~/one/two/three]"
}

#
# status and timer
#
# Neither is in the default shape, so these check they are there to be asked for.
#

@test "the status segment shows a failing exit code and nothing else" {
  z1_zsh 'zstyle ":z1:prompt" format "\$status"
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    r() { ( exit $1 ); print -Pn -- $PROMPT }
    print "ok: [$(r 0)]"
    print "fail: [${(V)$(r 3)}]"'
  assert_success
  assert_line "ok: []"
  assert_line "fail: [^[[38;5;160m3^[[39m]"
}

@test "the timer segment stays quiet under its threshold" {
  z1_zsh 'zstyle ":z1:prompt" format "(\$timer)"
    zstyle ":z1:prompt:segment:timer" threshold 5
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    z1_prompt_timer_elapsed=1.5
    z1-prompt-render
    print "quick: [$(print -Pn -- $PROMPT)]"
    z1_prompt_timer_elapsed=7.25
    z1-prompt-render
    print "slow: [${(V)$(print -Pn -- $PROMPT)}]"'
  assert_success
  assert_line "quick: []"
  assert_line "slow: [^[[38;5;178m7.2s^[[39m]"
}

@test "the timer counts minutes once there are any" {
  z1_zsh 'zstyle ":z1:prompt" format "\$timer"
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    z1_prompt_timer_elapsed=125
    z1-prompt-render
    print "mins: [${(V)$(print -Pn -- $PROMPT)}]"
    z1_prompt_timer_elapsed=3725
    z1-prompt-render
    print "hours: [${(V)$(print -Pn -- $PROMPT)}]"'
  assert_success
  assert_line "mins: [^[[38;5;178m2m5s^[[39m]"
  assert_line "hours: [^[[38;5;178m1h2m5s^[[39m]"
}

@test "the timer hooks measure a real command" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    z1-prompt-timer-preexec
    sleep 0.2
    z1-prompt-timer-precmd
    print "measured: $(( z1_prompt_timer_elapsed >= 0.15 && z1_prompt_timer_elapsed < 5 ))"
    z1-prompt-timer-precmd
    print "reset: $(( z1_prompt_timer_elapsed == 0 ))"'
  assert_success
  assert_line "measured: 1"
  assert_line "reset: 1"
}

#
# Transient prompt
#
# Transient collapses an accepted line to the character alone. It cannot be
# observed without a terminal repainting, so these check the parts: the widget
# binding, the collapsed string, and precmd putting the full prompt back. The
# style is read in precmd, so these call it rather than only loading.
#

@test "transient prompt is off by default" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    prompt_z1_precmd
    print "widget: ${widgets[accept-line]:-builtin}"
    print "transient: [$_prompt_z1_transient]"'
  assert_success
  assert_line "widget: builtin"
  assert_line "transient: []"
}

@test "the transient zstyle binds accept-line" {
  z1_zsh 'zstyle ":z1:prompt" transient yes
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    prompt_z1_precmd
    print "widget: ${widgets[accept-line]}"'
  assert_success
  assert_line "widget: user:prompt_z1_accept_line"
}

# Setting the style after the prompt is already running has to work, since that
# is how anyone tries it out.
@test "the style can be turned on after the prompt is initialized" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    prompt_z1_precmd
    print "before: ${widgets[accept-line]:-builtin}"
    zstyle ":z1:prompt" transient yes
    prompt_z1_precmd
    print "after: ${widgets[accept-line]:-builtin}"'
  assert_success
  assert_line "before: builtin"
  assert_line "after: user:prompt_z1_accept_line"
}

@test "the style can be turned off again" {
  z1_zsh 'zstyle ":z1:prompt" transient yes
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    prompt_z1_precmd
    print "on: ${widgets[accept-line]:-builtin}"
    zstyle ":z1:prompt" transient no
    prompt_z1_precmd
    print "off: ${widgets[accept-line]:-builtin}"
    print "transient: [$_prompt_z1_transient]"
    zstyle -d ":z1:prompt" transient
    zstyle ":z1:prompt" transient yes
    prompt_z1_precmd
    print "back on: ${widgets[accept-line]:-builtin}"'
  assert_success
  assert_line "on: user:prompt_z1_accept_line"
  assert_line "off: builtin"
  assert_line "transient: []"
  assert_line "back on: user:prompt_z1_accept_line"
}

@test "the collapsed prompt is the character in cyan, with no path" {
  z1_zsh 'zstyle ":z1:prompt" transient yes
    zstyle ":z1:prompt:character" success S
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    prompt_z1_precmd
    o=$(print -Pn -- $_prompt_z1_transient); print "transient: ${(V)o}"'
  assert_success
  assert_line "transient: ^[[38;5;37mS^[[39m "
}

# Cyan regardless of exit status, so scrollback has no red in it.
@test "the collapsed prompt keeps its color after a failure" {
  z1_zsh 'zstyle ":z1:prompt" transient yes
    zstyle ":z1:prompt:character" success S
    zstyle ":z1:prompt:character" error E
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    ( exit 1 ); prompt_z1_precmd
    o=$(print -Pn -- $_prompt_z1_transient); print "transient: ${(V)o}"'
  assert_success
  assert_line "transient: ^[[38;5;37mS^[[39m "
}

@test "precmd puts the full prompt back after a collapse" {
  z1_zsh 'zstyle ":z1:prompt" transient yes
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    PROMPT=$_prompt_z1_transient
    prompt_z1_precmd
    print "restored: $([[ $PROMPT == $_prompt_z1_full ]] && print yes || print no)"'
  assert_success
  assert_line "restored: yes"
}

# Unbinding only reverts a widget z1 installed, so another plugin's accept-line
# wrapper is left alone.
@test "another accept-line wrapper is not unbound" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    function other-accept-line { zle .accept-line }
    zle -N accept-line other-accept-line
    prompt_z1_precmd
    print "widget: ${widgets[accept-line]}"'
  assert_success
  assert_line "widget: user:other-accept-line"
}

#
# Cleanup
#

# Switching to another theme has to leave nothing of this one behind.
@test "switching away removes the prompt's hooks" {
  z1_zsh 'source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    print "before: $(( $precmd_functions[(I)z1-prompt-render] > 0 ))"
    prompt off
    print "precmd: $(( $precmd_functions[(I)prompt_z1_precmd] > 0 ))"
    print "render: $(( $precmd_functions[(I)z1-prompt-render] > 0 ))"'
  assert_success
  assert_line "before: 1"
  assert_line "precmd: 0"
  assert_line "render: 0"
}

@test "switching away gives back accept-line" {
  z1_zsh 'zstyle ":z1:prompt" transient yes
    source $Z1
    autoload -Uz promptinit && promptinit && prompt z1
    prompt_z1_precmd
    print "before: ${widgets[accept-line]}"
    prompt off
    print "after: ${widgets[accept-line]:-builtin}"'
  assert_success
  assert_line "before: user:prompt_z1_accept_line"
  assert_line "after: builtin"
}
