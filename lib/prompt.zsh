#!/usr/bin/env zsh
# prompt - build a prompt out of small, replaceable segments.
#
#   source /path/to/lib/prompt.zsh
#
#   function my-branch { REPLY=$vcs_info_msg_0_ }
#   z1-prompt-segment git my-branch
#
#   zstyle ':z1:prompt' format '$pwd( on $git)
#   $char '
#   z1-prompt-build
#
# The shape of the prompt is one format string, after starship's, but with only
# what zsh does not already do:
#
#   $name     what the segment called `name` produced
#   ${name}   the same, when the name runs into following text
#   (...)     a group that disappears unless something inside it has a value
#   \$ \(     a literal one of those, plus \) \\ \n \t
#
# Everything else is literal, zsh's own prompt escapes included, so `%~` and
# `%B` and `%(?..)` mean what they always did. Color is one of those, which is
# why the format has no styling syntax of its own: styling is the segment's job,
# and z1-prompt-style turns 'bold red' into the escapes for one. The right-hand
# prompt is its own format:
#   zstyle ':z1:prompt' right-format '$timer'
#
# A group is how an optional segment stops costing a stray separator: put the
# space inside the group, as in '( on $git)', and the space leaves with the
# segment. Groups nest, and a group holding no segment at all never shows.
#
# One thing to know about a group: braces end one early, so `%F{red}` written
# inside a group is handled for you, but a `%(?.a.b)` in there is not, and nor is
# a brace arriving from a segment marked -s. Keep both outside groups.
#
# A segment is a function that puts a prompt string in $REPLY. Segments run
# before every prompt, and an empty $REPLY makes the groups around them
# collapse. Two things a segment can ask for when it registers:
#
#   -s  static. Run once, at build, and written into the prompt as it stands,
#       so escapes inside it are re-read every time zsh draws. That is the only
#       way an exit status or a vi keymap survives a `zle reset-prompt`. Write
#       colors as $z1_prompt_fg[red] rather than %F{red}, so no brace ends up
#       somewhere it should not.
#   -n  no output of its own. It contributes nothing to whether a group shows.
#
# Slow segments belong in the background, which wants lib/async.zsh sourced
# first. Without it they run inline instead:
#   zstyle ':z1:prompt:segment:git' async 'yes'
#
# A segment can also be switched off without being taken out of the format:
#   zstyle ':z1:prompt:segment:git' disabled 'yes'

setopt prompt_subst

# name -> color number, and the ready-made escapes built from it. Segments read
# the escapes: a fragment reaching the prompt through a parameter has its %
# escapes honored, but gets no second round of $ expansion, so a segment that
# wrote '%F{$z1_prompt_palette[red]}' would reach the terminal as garbage.
typeset -gA z1_prompt_palette z1_prompt_fg z1_prompt_bg

# name -> character, from a style with a unicode/ascii default:
#   zstyle ':z1:prompt:character' dirty '!'
#   zstyle ':z1:prompt' ascii 'yes'
typeset -gA z1_prompt_char

# Segment bookkeeping: the function to call, its flags, whatever it produced
# last, the async task carrying it, and whether the format actually named it.
typeset -gA z1_prompt_segments z1_prompt_flags z1_prompt_frag z1_prompt_async
typeset -gA z1_prompt_used

# Escapes the compiled prompt refers to instead of holding. A style written into
# the prompt as %F{4} would be a brace inside a group, and braces end a group
# early, so the compiler parks them here and refers to them by number.
typeset -gA z1_prompt_esc
typeset -gi z1_prompt_nesc=0

# Say what the prompt decided, for anyone working out why a segment never
# showed up:
#   zstyle ':z1:prompt' debug 'yes'
function z1-prompt-debug() {
  zstyle -t ':z1:prompt' debug && print -ru2 -- "z1-prompt: $*"
  return 0
}

# Fill in the palette and the escapes built from it. z1-prompt-build calls this,
# so a style set afterwards lands on the next build.
function z1-prompt-palette() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  local -A defaults=(
    black 0 red 1 green 2 yellow 3 blue 4 magenta 5 cyan 6 white 7
  )

  # A 256-color terminal can do better than its own idea of "red".
  if [[ $TERM == *256color* || $TERM == *rxvt* ]]; then
    defaults=(
      black 000 red 160 green 076 yellow 178
      blue  039 magenta 168 cyan 037 white 255
    )
  fi

  z1_prompt_palette=("${(@kv)defaults}")

  # Whatever is set under the palette context wins, including names of your own.
  # Reading them back out of `zstyle -L` is what makes the extra names possible:
  # there is nothing to ask `zstyle -s` for when the name is not known up front.
  local line
  local -a fields
  for line in ${(f)"$(zstyle -L ':z1:prompt:palette')"}; do
    fields=(${(z)line})
    (( $#fields >= 4 )) || continue
    z1_prompt_palette[${(Q)fields[3]}]=${(Q)fields[4]}
  done

  local name
  z1_prompt_fg=() z1_prompt_bg=()
  for name in ${(k)z1_prompt_palette}; do
    z1_prompt_fg[$name]="%F{${z1_prompt_palette[$name]}}"
    z1_prompt_bg[$name]="%K{${z1_prompt_palette[$name]}}"
  done
}

# Resolve one character: a style wins, then the ascii form when asked for, then
# the unicode form.
#   z1-prompt-character dirty '•' '*'
function z1-prompt-character() {
  emulate -L zsh
  setopt local_options no_ksh_arrays
  (( $# >= 2 )) || return 1

  local name=$1 unicode=$2 ascii=${3:-$2} value
  if zstyle -s ':z1:prompt:character' $name value; then
    z1_prompt_char[$name]=$value
  elif zstyle -t ':z1:prompt' ascii; then
    z1_prompt_char[$name]=$ascii
  else
    z1_prompt_char[$name]=$unicode
  fi
}

# Turn a style list into prompt escapes, in $REPLY.
#   z1-prompt-style 'bold fg:accent bg:black'
function z1-prompt-style() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  local word fg= bg= out= off=
  local -i bold=0 uline=0

  for word in ${=1}; do
    case $word in
      none)      REPLY=; reply=('' ''); return 0 ;;
      bold)      bold=1  ;;
      underline) uline=1 ;;
      fg:*)      fg=${word#fg:} ;;
      bg:*)      bg=${word#bg:} ;;
      '')        ;;
      *)         fg=$word ;;
    esac
  done

  (( bold ))  && out+='%B'
  (( uline )) && out+='%U'
  # A palette name resolves, anything else goes to zsh as written, so both
  # 'accent' and '196' and 'red' work.
  [[ -n $fg ]] && out+="%F{${z1_prompt_palette[$fg]:-$fg}}"
  [[ -n $bg ]] && out+="%K{${z1_prompt_palette[$bg]:-$bg}}"

  # Turn off only what was turned on. Colors first, because zsh's %b resets
  # everything and then puts the current color back, which would undo itself.
  [[ -n $fg ]] && off+='%f'
  [[ -n $bg ]] && off+='%k'
  (( bold ))   && off+='%b'
  (( uline ))  && off+='%u'

  REPLY=$out
  reply=($out $off)
}

# Park an escape in the table and hand back a reference to it. See
# $z1_prompt_esc for why the compiler cannot write braces into a prompt.
function _z1-prompt-park() {
  z1_prompt_esc[$(( ++z1_prompt_nesc ))]=$1
  REPLY="\${z1_prompt_esc[$z1_prompt_nesc]}"
}

# Append literal text to the level being compiled, parking it first when writing
# it straight into the prompt would not survive.
#
# A '$' or a backtick is expanded when the prompt is drawn, so a literal one has
# to arrive through a parameter, whose value gets no second round of expansion. A
# brace ends a group early, so it needs the same treatment inside one.
#
# This reads $out and $cur from z1-prompt-compile, which is what makes it a
# helper rather than a function in its own right. A $cur above 1 means there is a
# group open around whatever is being emitted.
function _z1-prompt-emit() {
  local text=$1
  if [[ $text == *[\$\`]* ]] || { (( cur > 1 )) && [[ $text == *[{}]* ]] }; then
    local REPLY=
    _z1-prompt-park $text
    text=$REPLY
  fi
  out[cur]+=$text
}

# Build the test that decides whether a group shows: true when any one of the
# given expressions has a value.
function _z1-prompt-test() {
  local test
  local -i i

  if (( $# == 1 )); then
    REPLY=$1
    return 0
  fi

  test="\$$argv[-1]"
  for (( i = $# - 1; i >= 1; i-- )); do
    test="\${$argv[i]:-$test}"
  done
  REPLY=$test
}

# Compile a format string into a prompt string, in $REPLY. Segments named along
# the way are recorded in $z1_prompt_used, and parked escapes accumulate in
# $z1_prompt_esc, so the caller clears both before a fresh build.
function z1-prompt-compile() {
  emulate -L zsh
  setopt local_options no_ksh_arrays extended_glob

  local fmt=$1
  local -i i=1 n=$#fmt cur=1
  local ch nxt name bare rest tok body spec

  # One entry per open group: what it has built so far, and which segments it has
  # seen. Index 1 is the format itself, which nothing closes.
  local -a out=('') refs=('')

  while (( i <= n )); do
    ch=$fmt[i]

    # An escaped character is only ever itself.
    if [[ $ch == '\' ]]; then
      nxt=$fmt[i+1]
      case $nxt in
        n)  _z1-prompt-emit $'\n' ;;
        t)  _z1-prompt-emit $'\t' ;;
        '') _z1-prompt-emit '\'   ;;
        *)  _z1-prompt-emit $nxt  ;;
      esac
      (( i += 2 ))
      continue
    fi

    # A segment reference, either $name or ${name}.
    if [[ $ch == '$' ]]; then
      if [[ $fmt[i+1] == '{' ]]; then
        rest=$fmt[i+2,-1]
        name=${rest%%\}*}
        if [[ $name == $rest ]]; then     # no closing brace, so not a reference
          _z1-prompt-emit '$'
          (( i++ ))
          continue
        fi
        (( i += 3 + $#name ))
      else
        rest=$fmt[i+1,-1]
        name=${(M)rest##[A-Za-z_][A-Za-z0-9_]#}
        if [[ -z $name ]]; then
          _z1-prompt-emit '$'
          (( i++ ))
          continue
        fi
        (( i += 1 + $#name ))
      fi

      if [[ -z ${z1_prompt_segments[$name]} ]]; then
        z1-prompt-debug "no segment named '$name'"
        continue
      fi
      if zstyle -t ":z1:prompt:segment:$name" disabled; then
        continue
      fi
      z1_prompt_used[$name]=1

      # A static goes in as it stands, so the escapes inside it stay live.
      # Anything else is referred to, so a new value lands without recompiling.
      bare="z1_prompt_frag[$name]"
      if [[ ${z1_prompt_flags[$name]} == *static* ]]; then
        out[cur]+=${z1_prompt_frag[$name]}
      elif [[ -n ${z1_prompt_async[$name]} ]]; then
        bare="async_output[${z1_prompt_async[$name]}]"
        out[cur]+="\${$bare}"
      else
        out[cur]+="\${$bare}"
      fi

      # A segment with no output of its own gets no vote on whether the group
      # around it shows.
      [[ ${z1_prompt_flags[$name]} == *nosep* ]] \
        || refs[cur]+="${refs[cur]:+ }$bare"
      continue
    fi

    # A group, which shows only when something inside it does.
    if [[ $ch == '(' ]]; then
      out+=(''); refs+=('')
      (( cur++, i++ ))
      continue
    fi

    if [[ $ch == ')' ]] && (( cur > 1 )); then
      body=$out[cur]
      spec=$refs[cur]
      out[-1]=(); refs[-1]=()
      (( cur-- ))

      # A group naming no segment can never have a value, so it never shows.
      if [[ -n $spec ]]; then
        _z1-prompt-test ${=spec}
        out[cur]+="\${$REPLY:+$body}"
        refs[cur]+="${refs[cur]:+ }$spec"
      fi
      (( i++ ))
      continue
    fi

    # zsh's own escapes pass straight through, two characters at a time, so the
    # parenthesis in a %(...) never reads as the start of a group. A color takes
    # its argument in braces, and those have to travel together.
    if [[ $ch == '%' ]]; then
      nxt=$fmt[i+1]
      if [[ $nxt == (F|K) && $fmt[i+2] == '{' ]]; then
        tok="${fmt[i,-1]%%\}*}}"
        _z1-prompt-emit "$tok"
        (( i += $#tok ))
      else
        _z1-prompt-emit "$fmt[i,i+1]"
        (( i += 2 ))
      fi
      continue
    fi

    _z1-prompt-emit $ch
    (( i++ ))
  done

  # An unclosed group is a typo, not a reason to lose the prompt.
  while (( cur > 1 )); do
    z1-prompt-debug "unclosed group in format"
    body=$out[cur]
    out[-1]=(); refs[-1]=()
    (( cur-- ))
    out[cur]+=$body
  done

  REPLY=$out[1]
}

# Register a segment under a short name.
#   z1-prompt-segment [-s|--static] [-n|--nosep] <name> <function>
function z1-prompt-segment() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  local -a flags=()
  while [[ $1 == -?* ]]; do
    case $1 in
      -s|--static) flags+=(static) ;;
      -n|--nosep)  flags+=(nosep)  ;;
      *) print -ru2 -- "z1-prompt-segment: unknown option: $1"; return 1 ;;
    esac
    shift
  done
  [[ $1 == -- ]] && shift
  (( $# == 2 )) || return 1

  z1_prompt_segments[$1]=$2
  z1_prompt_flags[$1]="$flags"
  z1_prompt_frag[$1]=
  z1_prompt_async[$1]=
}

# Forget a segment. Its task, if it had one, goes with it.
function z1-prompt-unsegment() {
  emulate -L zsh
  setopt local_options no_ksh_arrays
  (( $# )) || return 1

  z1-prompt-untask $1
  unset "z1_prompt_segments[$1]" "z1_prompt_flags[$1]" "z1_prompt_frag[$1]" \
        "z1_prompt_async[$1]" "z1_prompt_used[$1]"
}

# Run one segment and keep what it produced. $REPLY is local, so a segment
# starts from empty and never clobbers a caller's.
function z1-prompt-refresh() {
  setopt local_options no_ksh_arrays
  local name=$1 fn=${z1_prompt_segments[$1]}

  if (( ! $+functions[$fn] )); then
    z1_prompt_frag[$name]=
    return 1
  fi

  local REPLY=
  $fn
  z1_prompt_frag[$name]=$REPLY
}

# Refresh the segments the format actually named. This is what precmd calls; the
# prompt itself was compiled at build and does not need rebuilding.
function z1-prompt-render() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  local name
  for name in ${(k)z1_prompt_used}; do
    [[ ${z1_prompt_flags[$name]} == *static* ]] && continue
    [[ -n ${z1_prompt_async[$name]} ]] && continue
    z1-prompt-refresh $name
  done
}

# Hand a segment to lib/async.zsh. Non-zero when it cannot, which is how the
# caller knows to keep running it inline.
function z1-prompt-task() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  local name=$1 fn=${z1_prompt_segments[$1]}
  (( $+functions[async-task] )) || return 1
  (( $+functions[$fn] )) || return 1

  # async.zsh collects stdout, so wrap the segment in something that prints
  # what it put in $REPLY.
  local wrapper=z1-prompt-async-$name
  functions[$wrapper]="local REPLY=; $fn; builtin print -rn -- \$REPLY"

  async-task z1-prompt-$name $wrapper || return 1
  z1_prompt_async[$name]=z1-prompt-$name
}

# Stop a segment's task and go back to running it inline.
function z1-prompt-untask() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  local name=$1
  [[ -n ${z1_prompt_async[$name]} ]] || return 0

  (( $+functions[async-untask] )) && async-untask ${z1_prompt_async[$name]}
  (( $+functions[z1-prompt-async-$name] )) && unfunction z1-prompt-async-$name
  z1_prompt_async[$name]=
}

# Read the styles, compile the format, and start rendering. Safe to call again
# after changing a style, which is how a prompt is re-themed.
function z1-prompt-build() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  z1-prompt-palette

  local name fmt
  local -a values

  # Static segments are resolved here, once, so the compiler can write them in.
  for name in ${(k)z1_prompt_segments}; do
    [[ ${z1_prompt_flags[$name]} == *static* ]] || continue
    z1-prompt-refresh $name
  done

  # Async is a style, so a segment can move between background and inline
  # between builds. Take everything off async, then put back what asks for it.
  for name in ${(k)z1_prompt_async}; do
    z1-prompt-untask $name
  done
  for name in ${(k)z1_prompt_segments}; do
    [[ ${z1_prompt_flags[$name]} == *static* ]] && continue
    zstyle -t ":z1:prompt:segment:$name" disabled && continue
    zstyle -t ":z1:prompt:segment:$name" async || continue
    z1-prompt-task $name || z1-prompt-debug "segment '$name' cannot go async"
  done

  # A style wins outright. Absent one, whatever is in $z1_prompt_format stands,
  # so a theme can ship a default layout and still be overridden.
  zstyle -a ':z1:prompt' format values && z1_prompt_format="${(j: :)values}"
  zstyle -a ':z1:prompt' right-format values \
    && z1_prompt_right_format="${(j: :)values}"

  z1_prompt_esc=()
  z1_prompt_nesc=0
  z1_prompt_used=()

  local REPLY=
  z1-prompt-compile "$z1_prompt_format";       PROMPT=$REPLY
  z1-prompt-compile "$z1_prompt_right_format"; RPROMPT=$REPLY

  # A segment nobody asked for has no business running in the background.
  for name in ${(k)z1_prompt_async}; do
    [[ -n ${z1_prompt_async[$name]} ]] || continue
    (( ${+z1_prompt_used[$name]} )) || z1-prompt-untask $name
  done

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd z1-prompt-render
  z1-prompt-render
}

# Stop rendering and let go of every task. A theme's cleanup wants this, so the
# next prompt does not inherit ours.
function z1-prompt-unbuild() {
  emulate -L zsh
  setopt local_options no_ksh_arrays

  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd z1-prompt-render

  local name
  for name in ${(k)z1_prompt_async}; do
    z1-prompt-untask $name
  done
  for name in ${(k)z1_prompt_frag}; do
    z1_prompt_frag[$name]=
  done
  z1_prompt_used=()
}

# The format a build falls back on. Set these to give a theme its own default.
typeset -g z1_prompt_format='$pwd $char'
typeset -g z1_prompt_right_format=''
