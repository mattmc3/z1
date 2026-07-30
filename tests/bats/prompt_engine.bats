#!/usr/bin/env bats
# lib/prompt.zsh builds a prompt from one format string, after starship's. A
# segment is a function that puts a prompt string in $REPLY; the format says
# where it goes, groups say when it shows, and styles say how it looks.
#
# The format is compiled once, at build, into a native zsh prompt string. So
# these check two things separately: what the compiler produced, and what zsh
# renders it to. `print -Pn` does the rendering a terminal would.

load helpers/common

setup() { z1_setup; }
teardown() { z1_teardown; }

# Segments covering the cases that matter: content, empty, and a second with
# content so a group can hold more than one.
segs() {
  echo 'source ${Z1:h}/lib/prompt.zsh
    function seg_a { REPLY=A }
    function seg_b { REPLY= }
    function seg_c { REPLY=C }
    z1-prompt-segment a seg_a
    z1-prompt-segment b seg_b
    z1-prompt-segment c seg_c
    render() { print -Pn -- $PROMPT }'
}

#
# Palette
#

@test "the palette defaults to the basic colors" {
  z1_zsh 'TERM=vt100
    source ${Z1:h}/lib/prompt.zsh
    z1-prompt-build
    for c in black red green yellow blue magenta cyan white; do
      print "$c: $z1_prompt_palette[$c]"
    done'
  assert_success
  assert_line "black: 0"
  assert_line "red: 1"
  assert_line "green: 2"
  assert_line "yellow: 3"
  assert_line "blue: 4"
  assert_line "magenta: 5"
  assert_line "cyan: 6"
  assert_line "white: 7"
}

@test "a 256-color terminal gets the extended palette" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    z1-prompt-build
    print "red: $z1_prompt_palette[red]"
    print "blue: $z1_prompt_palette[blue]"'
  assert_success
  assert_line "red: 160"
  assert_line "blue: 039"
}

# The old prompt only read the color styles on a 256-color terminal, so setting
# one did nothing anywhere else. A style wins on every terminal now.
@test "a palette style wins on a basic terminal too" {
  z1_zsh 'TERM=vt100
    zstyle ":z1:prompt:palette" red 9
    source ${Z1:h}/lib/prompt.zsh
    z1-prompt-build
    print "red: $z1_prompt_palette[red]"'
  assert_success
  assert_line "red: 9"
}

@test "the palette takes names of your own" {
  z1_zsh 'zstyle ":z1:prompt:palette" accent 214
    source ${Z1:h}/lib/prompt.zsh
    z1-prompt-build
    print "accent: $z1_prompt_palette[accent]"
    print "fg: $z1_prompt_fg[accent]"
    print "bg: $z1_prompt_bg[accent]"'
  assert_success
  assert_line "accent: 214"
  assert_line "fg: %F{214}"
  assert_line "bg: %K{214}"
}

# A fragment reaching the prompt through a parameter has its % escapes honored
# but gets no second round of $ expansion, so the color has to be baked into the
# fragment. $z1_prompt_fg is what a segment uses to do that.
@test "a color escape from the palette survives being substituted in" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    function seg_x { REPLY="$z1_prompt_fg[red]X%f" }
    z1-prompt-segment x seg_x
    zstyle ":z1:prompt" format "\$x"
    z1-prompt-build
    o=$(print -Pn -- $PROMPT); print "rendered: ${(V)o}"'
  assert_success
  assert_line "rendered: ^[[38;5;160mX^[[39m"
}

#
# Characters
#

@test "a character defaults to its unicode form" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    z1-prompt-character dirty "*" "+"
    print "dirty: $z1_prompt_char[dirty]"'
  assert_success
  assert_line "dirty: *"
}

@test "asking for ascii picks the fallback form" {
  z1_zsh 'zstyle ":z1:prompt" ascii yes
    source ${Z1:h}/lib/prompt.zsh
    z1-prompt-character dirty "*" "+"
    print "dirty: $z1_prompt_char[dirty]"'
  assert_success
  assert_line "dirty: +"
}

@test "a character style beats both forms" {
  z1_zsh 'zstyle ":z1:prompt" ascii yes
    zstyle ":z1:prompt:character" dirty "!"
    source ${Z1:h}/lib/prompt.zsh
    z1-prompt-character dirty "*" "+"
    print "dirty: $z1_prompt_char[dirty]"'
  assert_success
  assert_line "dirty: !"
}

@test "a character with no ascii form falls back to the unicode one" {
  z1_zsh 'zstyle ":z1:prompt" ascii yes
    source ${Z1:h}/lib/prompt.zsh
    z1-prompt-character branch "b"
    print "branch: $z1_prompt_char[branch]"'
  assert_success
  assert_line "branch: b"
}

#
# Styles
#
# The format has no styling syntax: color is a zsh prompt escape and zsh already
# has one. z1-prompt-style is a helper for segment authors, not part of the
# format grammar.

@test "a style list becomes prompt escapes" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    z1-prompt-palette
    for spec in "bold" "underline" "red" "fg:red" "bg:red" "bold underline red" "none" "196" "blue bg:black"; do
      z1-prompt-style $spec
      print "[$spec] $REPLY"
    done'
  assert_success
  assert_line "[bold] %B"
  assert_line "[underline] %U"
  assert_line "[red] %F{160}"
  assert_line "[fg:red] %F{160}"
  assert_line "[bg:red] %K{160}"
  assert_line "[bold underline red] %B%U%F{160}"
  assert_line "[none] "
  assert_line "[196] %F{196}"
  assert_line "[blue bg:black] %F{039}%K{000}"
}

# A color zsh already knows is passed through, so a style does not have to be in
# the palette to be usable.
@test "a color name outside the palette goes to zsh as written" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    z1-prompt-palette
    z1-prompt-style "bold chartreuse"
    print "style: $REPLY"'
  assert_success
  assert_line "style: %B%F{chartreuse}"
}

#
# Groups
#

@test "a group with nothing in it does not show" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a( on \$b)\$c"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [AC]"
}

@test "a group with something in it shows, text and all" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a( on \$c)"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [A on C]"
}

# Any one segment with a value is enough, which is what makes a group the answer
# to a stray separator.
@test "a group shows when any one of its segments has a value" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "( \$b\$c )"
    z1-prompt-build
    o=$(render); print "both: [$o]"
    zstyle ":z1:prompt" format "( \$b\$b )"
    z1-prompt-build
    o=$(render); print "neither: [$o]"'
  assert_success
  assert_line "both: [ C ]"
  assert_line "neither: []"
}

@test "groups nest" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a( on \$c( at \$b))"
    z1-prompt-build
    o=$(render); print "inner-empty: [$o]"
    zstyle ":z1:prompt" format "\$a( on \$c( at \$a))"
    z1-prompt-build
    o=$(render); print "inner-full: [$o]"'
  assert_success
  assert_line "inner-empty: [A on C]"
  assert_line "inner-full: [A on C at A]"
}

# Starship's rule: a group naming no variable can never have a value.
@test "a group holding only text never shows" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a(just text)\$c"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [AC]"
}

@test "an outer group notices a segment in an inner one" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "x( a( b \$c))x"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [x a b Cx]"
}

#
# Format syntax
#

@test "a reference can be braced to run into following text" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\${a}bc"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [Abc]"
}

@test "backslash escapes the format's own punctuation" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\\\$a \\( \\) \\[ \\] \$a"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line 'rendered: [$a ( ) [ ] A]'
}

@test "backslash-n is a newline" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a\\n\$c"
    z1-prompt-build
    print "rendered: [${$(render)//$'"'"'\n'"'"'/<NL>}]"'
  assert_success
  assert_line "rendered: [A<NL>C]"
}

@test "a literal newline in the format works too" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a
\$c"
    z1-prompt-build
    print "rendered: [${$(render)//$'"'"'\n'"'"'/<NL>}]"'
  assert_success
  assert_line "rendered: [A<NL>C]"
}

@test "an unknown segment name expands to nothing" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a\$nope\$c"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [AC]"
}

@test "the debug style says which name it did not know" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" debug yes
    zstyle ":z1:prompt" format "\$nope"
    z1-prompt-build 2>&1'
  assert_success
  assert_output_contains "nope"
}

@test "an unclosed group still yields a usable prompt" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a( on \$c"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [A on C]"
}

#
# zsh escapes in the format
#

@test "zsh's own prompt escapes pass through" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "%n \$a"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [$(id -un) A]"
}

# %(...) is zsh's ternary and has parentheses of its own. The compiler takes a
# prompt escape two characters at a time, so the '(' is consumed with the '%'
# rather than opening a group. The closing ')' has no group to close, so it is
# emitted as itself.
@test "a zsh ternary in the format is not read as a group" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "%(?.ok.bad) \$a"
    z1-prompt-build
    r() { ( exit $1 ); print -Pn -- $PROMPT }
    print "ok: [$(r 0)]"
    print "fail: [$(r 1)]"'
  assert_success
  assert_line "ok: [ok A]"
  assert_line "fail: [bad A]"
}

# A brace inside a group would close the group early, so the compiler parks the
# escape and refers to it instead.
@test "a color escape written by hand inside a group still works" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "( %F{160}\$c%f )"
    z1-prompt-build
    o=$(render); print "full: ${(V)o}"
    zstyle ":z1:prompt" format "( %F{160}\$b%f )"
    z1-prompt-build
    o=$(render); print "empty: [$o]"'
  assert_success
  assert_line "full:  ^[[38;5;160mC^[[39m "
  assert_line "empty: []"
}

#
# Right prompt
#

@test "the right format becomes RPROMPT" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt" format "\$a"
    zstyle ":z1:prompt" right-format "\$c"
    z1-prompt-build
    print "prompt: [$(render)]"
    print "rprompt: [$(print -Pn -- $RPROMPT)]"'
  assert_success
  assert_line "prompt: [A]"
  assert_line "rprompt: [C]"
}

# A theme wants a default format that a user style still overrides.
@test "a preset format is used when no style is set" {
  z1_zsh "$(segs)"'
    z1_prompt_format="\$a-\$c"
    z1-prompt-build
    print "preset: [$(render)]"
    zstyle ":z1:prompt" format "\$c"
    z1-prompt-build
    print "styled: [$(render)]"'
  assert_success
  assert_line "preset: [A-C]"
  assert_line "styled: [C]"
}

#
# Static segments
#

# A static is resolved once and written into the prompt as it stands, so escapes
# inside it are re-read every time zsh draws. That is the only way an exit status
# or a vi keymap survives a zle reset-prompt.
@test "a static segment keeps its escapes for the prompt to expand" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    function seg_st { REPLY="%(?.OK.FAIL)" }
    z1-prompt-segment -s st seg_st
    zstyle ":z1:prompt" format "\$st"
    z1-prompt-build
    print "raw: [$PROMPT]"
    r() { ( exit $1 ); print -Pn -- $PROMPT }
    print "ok: $(r 0)"
    print "fail: $(r 1)"'
  assert_success
  assert_line "raw: [%(?.OK.FAIL)]"
  assert_line "ok: OK"
  assert_line "fail: FAIL"
}

# A static's $ references stay live too, which a referred-to fragment's would
# not. That is what a vi keymap character needs.
@test "a static segment keeps its parameter references live" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    z1-prompt-character main "M"
    z1-prompt-character vicmd "V"
    function seg_ch { REPLY='"'"'${z1_prompt_char[${KEYMAP:-main}]:-?}'"'"' }
    z1-prompt-segment -s ch seg_ch
    zstyle ":z1:prompt" format "\$ch"
    z1-prompt-build
    r() { KEYMAP=$1; print -Pn -- $PROMPT }
    print "main: $(r main)"
    print "vicmd: $(r vicmd)"'
  assert_success
  assert_line "main: M"
  assert_line "vicmd: V"
}

# Colors in a static go in as $z1_prompt_fg[...], not %F{...}, so no brace ends
# up inside a group.
@test "a static segment can be styled inside a group" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    function seg_st { REPLY='"'"'$z1_prompt_fg[red]%(?.OK.FAIL)%f'"'"' }
    function seg_c { REPLY=C }
    z1-prompt-segment -s st seg_st
    z1-prompt-segment c seg_c
    zstyle ":z1:prompt" format "( \$c \$st )"
    z1-prompt-build
    o=$( ( exit 0 ); print -Pn -- $PROMPT ); print "rendered: ${(V)o}"'
  assert_success
  assert_line "rendered:  C ^[[38;5;160mOK^[[39m "
}

@test "a static segment is resolved once, not on every render" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    typeset -gi calls=0
    function seg_st { (( calls++ )); REPLY=S }
    z1-prompt-segment -s st seg_st
    zstyle ":z1:prompt" format "\$st"
    z1-prompt-build
    z1-prompt-render
    z1-prompt-render
    print "calls: $calls"'
  assert_success
  assert_line "calls: 1"
}

@test "a dynamic segment is re-run on every render" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    typeset -gi calls=0
    function seg_d { (( calls++ )); REPLY=D$calls }
    z1-prompt-segment d seg_d
    zstyle ":z1:prompt" format "\$d"
    z1-prompt-build
    z1-prompt-render
    print "calls: $calls"
    print "rendered: [$(print -Pn -- $PROMPT)]"'
  assert_success
  assert_line "calls: 2"
  assert_line "rendered: [D2]"
}

# The prompt is compiled once, so a new value shows up without rebuilding.
@test "a new value lands without recompiling the prompt" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    function seg_d { REPLY=$value }
    z1-prompt-segment d seg_d
    zstyle ":z1:prompt" format "x\$d"
    value=one
    z1-prompt-build
    before=$PROMPT
    print "first: [$(print -Pn -- $PROMPT)]"
    value=two
    z1-prompt-render
    print "second: [$(print -Pn -- $PROMPT)]"
    print "same prompt: $([[ $PROMPT == $before ]] && print yes || print no)"'
  assert_success
  assert_line "first: [xone]"
  assert_line "second: [xtwo]"
  assert_line "same prompt: yes"
}

@test "a segment named twice is computed once" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    typeset -gi calls=0
    function seg_d { (( calls++ )); REPLY=D }
    z1-prompt-segment d seg_d
    zstyle ":z1:prompt" format "\$d\$d"
    zstyle ":z1:prompt" right-format "\$d"
    z1-prompt-build
    print "calls: $calls"
    print "prompt: [$(print -Pn -- $PROMPT)]"
    print "rprompt: [$(print -Pn -- $RPROMPT)]"'
  assert_success
  assert_line "calls: 1"
  assert_line "prompt: [DD]"
  assert_line "rprompt: [D]"
}

@test "a segment nobody named is never run" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    typeset -gi calls=0
    function seg_d { (( calls++ )); REPLY=D }
    function seg_a { REPLY=A }
    z1-prompt-segment d seg_d
    z1-prompt-segment a seg_a
    zstyle ":z1:prompt" format "\$a"
    z1-prompt-build
    z1-prompt-render
    print "calls: $calls"'
  assert_success
  assert_line "calls: 0"
}

@test "a segment does not see the engine's own REPLY" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    function seg_r { print "saw: [$REPLY]"; REPLY=R }
    z1-prompt-segment r seg_r
    zstyle ":z1:prompt" format "\$r"
    REPLY=caller
    z1-prompt-build
    print "caller: [$REPLY]"'
  assert_success
  assert_line "saw: []"
  assert_line "caller: [caller]"
}

#
# Disabled
#

@test "a disabled segment drops out of the prompt" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt:segment:c" disabled yes
    zstyle ":z1:prompt" format "\$a( on \$c)"
    z1-prompt-build
    o=$(render); print "rendered: [$o]"'
  assert_success
  assert_line "rendered: [A]"
}

@test "a disabled segment is not run" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    typeset -gi calls=0
    function seg_d { (( calls++ )); REPLY=D }
    z1-prompt-segment d seg_d
    zstyle ":z1:prompt:segment:d" disabled yes
    zstyle ":z1:prompt" format "\$d"
    z1-prompt-build
    z1-prompt-render
    print "calls: $calls"'
  assert_success
  assert_line "calls: 0"
}

@test "a segment can be enabled again" {
  z1_zsh "$(segs)"'
    zstyle ":z1:prompt:segment:c" disabled yes
    zstyle ":z1:prompt" format "\$a\$c"
    z1-prompt-build
    print "off: [$(render)]"
    zstyle ":z1:prompt:segment:c" disabled no
    z1-prompt-build
    print "on: [$(render)]"'
  assert_success
  assert_line "off: [A]"
  assert_line "on: [AC]"
}

#
# Hooks
#

@test "build installs the render hook once" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    z1-prompt-build
    z1-prompt-build
    print "hooks: ${(M)#precmd_functions:#z1-prompt-render}"'
  assert_success
  assert_line "hooks: 1"
}

@test "unbuild removes the render hook" {
  z1_zsh 'source ${Z1:h}/lib/prompt.zsh
    z1-prompt-build
    z1-prompt-unbuild
    print "hooks: ${(M)#precmd_functions:#z1-prompt-render}"'
  assert_success
  assert_line "hooks: 0"
}

#
# Async
#

@test "a segment marked async runs through lib/async.zsh" {
  z1_zsh 'source ${Z1:h}/lib/async.zsh
    source ${Z1:h}/lib/prompt.zsh
    function seg_g { REPLY="$z1_prompt_fg[magenta]main%f" }
    z1-prompt-segment g seg_g
    zstyle ":z1:prompt:segment:g" async yes
    zstyle ":z1:prompt" format "\$g"
    z1-prompt-build
    print "prompt: [$PROMPT]"
    print "task: ${async_tasks[z1-prompt-g]}"
    async-run; async-wait
    o=$(print -Pn -- $PROMPT); print "rendered: ${(V)o}"'
  assert_success
  assert_line 'prompt: [${async_output[z1-prompt-g]}]'
  assert_line "task: z1-prompt-async-g"
  assert_line "rendered: ^[[38;5;168mmain^[[39m"
}

# An async value arrives between prompts, so the prompt has to refer to it rather
# than hold a copy, and a group around it has to collapse on its own when the
# value is empty.
@test "a group around an async segment collapses when it is empty" {
  z1_zsh "$(segs)"'
    source ${Z1:h}/lib/async.zsh
    function seg_g { REPLY= }
    z1-prompt-segment g seg_g
    zstyle ":z1:prompt:segment:g" async yes
    zstyle ":z1:prompt" format "\$a( on \$g)\$c"
    z1-prompt-build
    async-run; async-wait
    print "empty: [$(render)]"
    function seg_g { REPLY=G }
    async-run; async-wait
    print "full: [$(render)]"'
  assert_success
  assert_line "empty: [AC]"
  assert_line "full: [A on GC]"
}

@test "an async segment counts toward an outer group too" {
  z1_zsh "$(segs)"'
    source ${Z1:h}/lib/async.zsh
    function seg_g { REPLY= }
    z1-prompt-segment g seg_g
    zstyle ":z1:prompt:segment:g" async yes
    zstyle ":z1:prompt" format "x( a( b \$g))x"
    z1-prompt-build
    async-run; async-wait
    print "empty: [$(render)]"
    function seg_g { REPLY=G }
    async-run; async-wait
    print "full: [$(render)]"'
  assert_success
  assert_line "empty: [xx]"
  assert_line "full: [x a b Gx]"
}

# lib/async.zsh is optional, so an async segment has to still work without it.
@test "an async segment falls back to running inline" {
  z1_zsh "$(segs)"'
    function seg_g { REPLY=G }
    z1-prompt-segment g seg_g
    zstyle ":z1:prompt:segment:g" async yes
    zstyle ":z1:prompt" format "\$a( on \$g)"
    z1-prompt-build
    print "async: $(( $+functions[async-task] ))"
    print "rendered: [$(render)]"'
  assert_success
  assert_line "async: 0"
  assert_line "rendered: [A on G]"
}

@test "unbuild drops the async task" {
  z1_zsh 'source ${Z1:h}/lib/async.zsh
    source ${Z1:h}/lib/prompt.zsh
    function seg_g { REPLY=G }
    z1-prompt-segment g seg_g
    zstyle ":z1:prompt:segment:g" async yes
    zstyle ":z1:prompt" format "\$g"
    z1-prompt-build
    print "before: ${async_tasks[z1-prompt-g]:-none}"
    z1-prompt-unbuild
    print "after: ${async_tasks[z1-prompt-g]:-none}"'
  assert_success
  assert_line "before: z1-prompt-async-g"
  assert_line "after: none"
}

# Turning async off has to stop the task, not leave it running beside a segment
# that is now also being called inline.
@test "taking a segment out of async stops its task" {
  z1_zsh 'source ${Z1:h}/lib/async.zsh
    source ${Z1:h}/lib/prompt.zsh
    function seg_g { REPLY=G }
    z1-prompt-segment g seg_g
    zstyle ":z1:prompt:segment:g" async yes
    zstyle ":z1:prompt" format "\$g"
    z1-prompt-build
    print "on: ${async_tasks[z1-prompt-g]:-none}"
    zstyle ":z1:prompt:segment:g" async no
    z1-prompt-build
    print "off: ${async_tasks[z1-prompt-g]:-none}"
    print "rendered: [$(print -Pn -- $PROMPT)]"'
  assert_success
  assert_line "on: z1-prompt-async-g"
  assert_line "off: none"
  assert_line "rendered: [G]"
}

# A background job for a segment the format never names is wasted work.
@test "an async segment nobody named gets no task" {
  z1_zsh 'source ${Z1:h}/lib/async.zsh
    source ${Z1:h}/lib/prompt.zsh
    function seg_g { REPLY=G }
    function seg_a { REPLY=A }
    z1-prompt-segment g seg_g
    z1-prompt-segment a seg_a
    zstyle ":z1:prompt:segment:g" async yes
    zstyle ":z1:prompt" format "\$a"
    z1-prompt-build
    print "task: ${async_tasks[z1-prompt-g]:-none}"'
  assert_success
  assert_line "task: none"
}
