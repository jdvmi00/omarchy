# Marvell Wi-Fi firmware is for Intel Surface models.
if [[ $(uname -m) == "x86_64" ]] && omarchy-hw-surface; then
  omarchy-pkg-add linux-firmware-marvell
fi
