# z1

[![MIT License](https://img.shields.io/badge/license-MIT-007EC7.svg)](/LICENSE)
![version](https://img.shields.io/badge/version-v2.0.0-orange)

> First things first - start your .zshrc off right

## Description

`z1` is designed to be a portable, lightweight, ultra-fast, Zsh configuration in a
single file. Equally useful on your desktop machine or on a remote server, z1
enables much of the useful functionality already built into Zsh without the need for
frameworks. And, it's ridiculously fast!

`z1`'s goal of giving you a great starter DIY Zsh experience in a single file
stands in contrast to other full Zsh Frameworks like [Oh-My-Zsh][ohmyzsh] and
[Prezto][prezto]. Those frameworks are nice if you want everything-and-the-kitchen-sink,
but you pay a performance and complexity penalty for using these frameworks.

Many prefer to build their own Zsh config from scratch, but that can be a lot of work
and often requires you to pull together functionality already baked into the Zsh
frameworks you leave behind.

`z1` is simpler. Similar to [Grml's .zshrc][grml-zshrc], `z1` gives you
everything you need for a full-featured Zsh config, but contained in one simple to grok
Zsh include that will grow with you as you use Zsh. It is heavily inspired by the [Fish
shell][fish].

Feel free to use it as-is, build off it, or fork it and make it entirely your own.

## Features

- Set common Zsh environment variables
- Enable better Zsh options than the defaults
- Set better Zsh history options and variables
- Colorize output of commands like `ls`, `grep`, `diff`, and `man`
- Sensible line editor setup with vi/emacs keymap selection, cursor-style hints, and common terminal key fixes
- Useful zle widgets like `prepend-sudo`, `pound-toggle`, `edit-command-line`, paste magic, and quote magic
- Configure Zsh built-in completion system with cached `compinit` for fast startup
- Use built-in Zsh prompt system, with prompts found in your own `prompts/` directory
- Initialize Homebrew automatically when present

## Installation

Clone `z1` and source it from your `.zshrc`:

```zsh
git clone https://github.com/mattmc3/z1 ${ZDOTDIR:-$HOME}/.z1
```

```zsh
# .zshrc
source ${ZDOTDIR:-$HOME}/.z1/z1.zsh
```

Or download the single `z1.zsh` file and make it your own.

```zsh
curl -fsSL https://raw.githubusercontent.com/mattmc3/z1/main/z1.zsh -o ${ZDOTDIR:-$HOME}/z1.zsh
```

```zsh
# .zshrc
source ${ZDOTDIR:-$HOME}/z1.zsh
```

Or use a Zsh plugin manager, which will load `z1.plugin.zsh` for you. With
[antidote][antidote]:

```zsh
# .zsh_plugins.txt
mattmc3/z1
```

Or, using dynamic plugins without a .zsh_plugins.txt file:

```zsh
# .zshrc
source <(antidote init)
antidote bundle mattmc3/z1
```

Since `z1` sets up the basics everything else builds on, list it first.

## Configuration

`z1` is configured with zstyles. Set them in `$ZDOTDIR/.zstyles`, which `z1`
sources for you, or anywhere in your `.zshrc` before `z1` loads.

| Context            | Style       | Default                                    | What it does                                                      |
| ------------------ | ----------- | ------------------------------------------ | ----------------------------------------------------------------- |
| `:z1:color`        | `cache`     | off                                        | Cache `dircolors --sh` output rather than running it each startup |
| `:z1:compinit`     | `cache`     | off                                        | Cache the completion dumpfile and take `compinit`'s fast path     |
| `:z1:compinit`     | `dumpfile`  | `$ZSH_CACHE_DIR/ZSH_COMPDUMP-$ZSH_VERSION` | Where the completion dumpfile lives                               |
| `:z1:confd`        | `directory` | `$ZSH_CONFIG_DIR/conf.d`                   | Directory of config files to source at the end of your `.zshrc`   |
| `:z1:editor`       | `keymap`    | `emacs`                                    | Line editor keymap. Set it to `vi` for vi mode                    |
| `:z1:editor:emacs` | `cursor`    | `line`                                     | Cursor shape in emacs mode                                        |
| `:z1:editor:vicmd` | `cursor`    | `block`                                    | Cursor shape in vi command mode                                   |
| `:z1:editor:viins` | `cursor`    | `line`                                     | Cursor shape in vi insert mode                                    |
| `:z1:history`      | `histfile`  | `$ZSH_DATA_DIR/zsh_history`                | Where history is written                                          |
| `:z1:history`      | `histsize`  | `50000`                                    | Events kept in the current session                                |
| `:z1:history`      | `savehist`  | `100000`                                   | Events kept in the history file                                   |
| `:z1:homebrew`     | `cache`     | off                                        | Cache `brew shellenv` output rather than running it each startup  |
| `:z1:path`         | `prepath`   | `~/bin ~/sbin ~/.local/bin ~/.local/sbin`  | Entries kept at the front of `$path`                              |
| `:z1:post_zshrc`   | `debug`     | off                                        | Print each `post_zshrc` hook as it runs                           |
| `:z1:zstyles`      | `loaded`    | off                                        | Set it yourself to stop `z1` sourcing your `.zstyles`             |

Of the `prepath` defaults, only the directories that exist are used. Cursor
shapes are `block`, `underscore`, and `line`, each also with a `-blink`
suffix, and are only emitted on terminals that understand DECSCUSR.

```zsh
# .zstyles
zstyle ':z1:history' savehist 500000
zstyle ':z1:confd' directory "$ZSH_CONFIG_DIR/rc.d"
```

Caching is off by default because a cache hides a change until it expires, after
20 hours. Every cache shares the style name `cache`, so one pattern turns them
all on:

```zsh
zstyle ':z1:*' cache 'yes'
```

Use `cached-eval --clear` to empty the caches by hand, and `compinit`'s cache
rebuilds itself whenever `$fpath` changes.

### Prompt

`z1` adds `$ZSH_CONFIG_DIR/prompts` and its own `prompts/` directory to `fpath`,
yours first. Starting zsh's prompt system is left to you:

```zsh
# .zshrc
autoload -Uz promptinit && promptinit
prompt z1
```

The prompt is one format string, so rearranging it does not mean rewriting it.
`$name` is a segment, and `(...)` is a group that disappears unless something
inside it has a value, which is how an optional segment avoids leaving a stray
separator behind:

```zsh
# .zstyles
zstyle ':z1:prompt' format '$pwd( on $git)( took $timer)
$char '
zstyle ':z1:prompt' right-format '$status'
```

Segments that ship with it: `pwd`, `git`, `char`, `status`, `timer`. The default
shape uses the first three. Writing your own is a function that puts a prompt
string in `$REPLY`:

```zsh
# .zshrc, after `prompt z1`
function my-k8s-context { REPLY=$(kubectl config current-context 2>/dev/null) }
z1-prompt-segment k8s my-k8s-context
zstyle ':z1:prompt:segment:k8s' async 'yes'   # keep it off the critical path
zstyle ':z1:prompt' format '$pwd( ⎈ $k8s) $char '
z1-prompt-build
```

The bundled `z1` prompt reads these:

| Context                        | Style                                                          | Default           | What it does                                                              |
| ------------------------------ | -------------------------------------------------------------- | ----------------- | ------------------------------------------------------------------------- |
| `:z1:prompt`                   | `format`                                                       | `$pwd $char `     | The shape of the prompt                                                   |
| `:z1:prompt`                   | `right-format`                                                 | `$git`            | The same, for the right-hand prompt                                       |
| `:z1:prompt`                   | `pwd-length`                                                   | short             | `full` for `$PWD`, `long` for a `~`-shortened path, otherwise abbreviated |
| `:z1:prompt`                   | `transient`                                                    | off               | Collapse an accepted line to just the prompt character                    |
| `:z1:prompt`                   | `ascii`                                                        | off               | Fall back to ASCII symbols                                                |
| `:z1:prompt`                   | `debug`                                                        | off               | Say why a segment never showed up                                         |
| `:z1:prompt:character`         | `success` `error` `vicmd` `stash` `dirty` `ahead` `behind`     | `❯ ❯ ❮ ☰ • ⇡ ⇣`   | Symbols the prompt is built from                                          |
| `:z1:prompt:palette`           | `black` `red` `green` `yellow` `blue` `magenta` `cyan` `white` | 256-color palette | Color numbers the prompt is built from, plus any name of your own         |
| `:z1:prompt:segment:<name>`    | `async`                                                        | on for `git`      | Run the segment in the background, given `lib/async.zsh`                  |
| `:z1:prompt:segment:<name>`    | `disabled`                                                     | off               | Leave the segment out without editing the format                          |
| `:z1:prompt:segment:timer`     | `threshold`                                                    | 5                 | Seconds a command has to take before the timer says anything              |

`lib/prompt.zsh` is the engine on its own, with no segments and no opinions about
what a prompt looks like, if you would rather build one from scratch.

### Variables

A few things are plain variables, because they are read before any zstyle could
be set, or are conventional names from elsewhere.

| Variable         | Default                                 | What it does                                    |
| ---------------- | --------------------------------------- | ----------------------------------------------- |
| `ZFUNCDIR`       | `$ZSH_CONFIG_DIR/functions`             | Directory of functions to autoload              |
| `ZSH_BINDKEY`    | see `:z1:editor` `keymap`               | Wins over the zstyle when set before `z1` loads |
| `ZSH_COMPDUMP`   | see `:z1:compinit` `dumpfile`           | Wins over the zstyle when set before `z1` loads |
| `ZSH_CONFIG_DIR` | `$ZDOTDIR`, else `$XDG_CONFIG_HOME/zsh` | Where your config lives                         |
| `ZSH_DATA_DIR`   | `$XDG_DATA_HOME/zsh`                    | Where data that should persist lives            |
| `ZSH_CACHE_DIR`  | `$XDG_CACHE_HOME/zsh`                   | Where throwaway data lives                      |

[antidote]: https://antidote.sh
[fish]: https://fishshell.com
[ohmyzsh]: https://github.com/ohmyzsh/ohmyzsh
[prezto]: https://github.com/sorin-ionescu/prezto
[grml-zshrc]: https://github.com/grml/grml-etc-core/blob/master/etc/zsh/zshrc
