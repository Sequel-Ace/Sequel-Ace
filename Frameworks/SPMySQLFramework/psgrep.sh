#! /usr/bin/env bash
PORT=$1

for pid in $(/usr/bin/pgrep -f "ssh -L $PORT"); do kill -s HUP "$pid"; done
for pid in $(/usr/bin/pgrep -f "ssh -L $PORT"); do kill -s TERM "$pid"; done
for pid in $(/usr/bin/pgrep -f "ssh -L $PORT"); do kill -s KILL "$pid"; done

exit 0;
