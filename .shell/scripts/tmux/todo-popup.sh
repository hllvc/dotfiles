#!/usr/bin/env zsh

# prefix C-t: the todo file of the pane's repo in a popup (lua/todo in the nvim config).
# TODO_POPUP carries the origin pane, so `q` quits the popup and following an @src
# jumps back into that pane.
export TODO_POPUP="$1"
exec nvim -c 'lua require("todo").open()'
