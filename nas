#!/bin/bash

trap 'echo -e "\nAfgebroken"; exit 1' INT

connect_ssh() {
  local host="$1"

  echo "Verbinden met $host..."

  # BELANGRIJK: geen /bin/sh hier
  ssh -tt "$host"

  echo "Verbinding gesloten."
}

clear
echo "---------------------------------"
echo "Welke NAS wil je beheren (1/2)?"
echo "---------------------------------"

read -r myChoice

case $myChoice in
  1)
    connect_ssh "admin@192.168.0.220"
    ;;
  2)
    connect_ssh "admin@192.168.0.225"
    ;;
  *)
    echo "Geen geldige keuze"
    ;;
esac
