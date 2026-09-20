#!/usr/bin/env bash
for i in volume battery wifi cpu memory clock bluetooth ai display; do
  sketchybar --set $i popup.drawing=off 2>/dev/null
done
