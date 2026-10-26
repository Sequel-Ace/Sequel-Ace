#!/bin/zsh -f
#
# ssh-agent-relay.zsh <agent-socket>
#
# Sequel Ace SSH agent helper.
#
# Sequel Ace is sandboxed, so the ssh it launches cannot open an SSH agent's
# socket (1Password, Secretive, the system agent, ...). This script runs
# outside the sandbox and relays connections to the agent. It copies bytes and
# nothing else.
#
# It is deliberately narrow:
#   - It creates no files and takes no path to listen on. Sequel Ace opens a
#     socket inside its own container and hands it over as standard output;
#     this script only accepts connections on it.
#   - It connects only to sockets listed in ssh-agent-relay.allow, the text
#     file next to this script. Sequel Ace cannot write that file; you can.
#     Links are followed first: what must be listed is where the path really
#     leads, and the socket there must belong to you.
#   - It exits when Sequel Ace closes its standard input, i.e. when the app
#     quits or crashes.
#
# First line on standard error is "ready" or "error <reason>".

fail() {
	print -r -u2 -- "error $1"
	print -r -u2 -- "ssh-agent-relay: $2"
	exit $3
}

zmodload zsh/net/socket zsh/system 2>/dev/null || fail socket-module "zsh/net/socket is not available" 70

[[ $# -eq 1 ]] || fail usage "expected one argument, the agent socket to relay to" 64
target=$1

# The allowlist sits next to this script, which is installed at
#   <home>/Library/Application Scripts/<bundle id>/ssh-agent-relay.zsh
script_dir=${0:A:h}
home=${script_dir:h:h:h}
[[ $script_dir == "$home/Library/Application Scripts/${script_dir:t}" ]] || fail bad-location "not installed in an Application Scripts folder" 64

# Only relay to sockets the user has listed.
allowlist="$script_dir/ssh-agent-relay.allow"
[[ -r $allowlist ]] || fail no-allowlist "$allowlist is missing" 69
[[ $target == /* && $target != *//* && "$target/" != */../* && "$target/" != */./* && $target != *[[:cntrl:]]* ]] || fail not-allowed "the agent socket must be a plain absolute path" 67

# Match where the path really leads, not how it is spelled. Some listed
# locations sit in folders others can write to (/tmp); a link planted there
# under a listed name must not become a way to reach an unlisted socket.
given=$target
target=${target:A}

allowed=0
target_parts=("${(@s:/:)target}")
while IFS= read -r line || [[ -n $line ]]; do
	# Trim surrounding whitespace (and a CR from Windows line endings). Written
	# without "#" repetition, which needs EXTENDED_GLOB and "zsh -f" has it off.
	line=${line#"${line%%[![:space:]]*}"}
	# "#" starts a comment at the start of a line or after whitespace only.
	# A "#" inside a path is part of the path: cutting there would turn the
	# line into permission for a different, shorter path.
	[[ $line == \#* ]] && continue
	line=${line%%[[:space:]]\#*}
	line=${line%"${line##*[![:space:]]}"}
	[[ -n $line ]] || continue
	[[ $line == \~/* ]] && line="$home/${line#\~/}"
	# Only absolute paths count; a relative line would mean "relative to
	# wherever the helper happens to run".
	[[ $line == /* ]] || continue
	# Listed paths may be spelled through a link too (/tmp, /var, ~/.1password).
	[[ $line != *\** ]] && line=${line:A}
	pattern_parts=("${(@s:/:)line}")
	(( ${#pattern_parts} == ${#target_parts} )) || continue
	matched=1
	for (( i = 1; i <= ${#pattern_parts}; i++ )); do
		# "*" matches within one path component; every other character is literal.
		glob=${${(b)pattern_parts[i]}//\\\*/*}
		[[ $target_parts[i] == ${~glob} ]] || { matched=0; break }
	done
	(( matched )) && { allowed=1; break }
done < $allowlist
(( allowed )) || fail "not-allowed $target" "$target is not listed in $allowlist" 67
[[ -S $target ]] || fail no-target "$target is not a socket (is the agent running?)" 68
# An agent runs as you. A socket someone else created at a listed path — in a
# shared folder such as /tmp, say — is not your agent.
[[ -O $target ]] || fail not-owned "$target belongs to another user" 67

# Standard output is the listening socket; standard input is the lifeline.
exec {listen_fd}<&1 {control_fd}<&0
exec 1>/dev/null 0</dev/null
main_pid=$$

# Ends every child this shell has started. The list comes from the shell's own
# job table, so a child is covered from the moment it exists: there is no gap
# between starting one and remembering its process id.
end_children() {
	local pids=(${${(v)jobstates##*:*:}%=*})
	(( ${#pids} )) && kill $pids 2>/dev/null
}

shutdown() {
	end_children
	exit 0
}
trap shutdown TERM INT HUP

# Sequel Ace keeps our standard input open for as long as it runs. If this
# script was killed in the meantime the watcher has been re-parented, and the
# process id it remembers may belong to something else by now.
{
	# Only the main loop accepts; a watcher outliving it must not keep the
	# socket open and leave clients hanging.
	exec {listen_fd}<&-
	/bin/cat <&$control_fd >/dev/null
	(( $sysparams[ppid] == main_pid )) && kill -TERM $main_pid 2>/dev/null
} &

print -r -u2 -- "ready"

while true; do
	zsocket -a $listen_fd 2>/dev/null || continue
	client_fd=$REPLY
	(
		exec {control_fd}<&- {listen_fd}<&-
		# In place before anything is started, so being told to quit at any
		# point ends both pumps and closes the connection to the agent. When
		# either direction ends (CHLD), the other is ended too.
		trap 'end_children; exit 0' TERM INT HUP CHLD
		# This script runs for as long as the app does. Check again that the
		# path still leads to the same socket of yours that was approved.
		[[ ${given:A} == $target && -S $target && -O $target ]] || exit 1
		zsocket -- $target 2>/dev/null || exit 1
		agent_fd=$REPLY
		/bin/cat <&$agent_fd >&$client_fd &
		/bin/cat <&$client_fd >&$agent_fd &
		wait
	) &
	exec {client_fd}<&-
done
