#!/bin/sh

rofi -theme search -dmenu | xargs -I{} xdg-open https://www.google.de/search\?q\=\{\}
