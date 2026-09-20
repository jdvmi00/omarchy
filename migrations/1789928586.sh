echo "Retain the installed ARM Limine recovery packages during orphan cleanup"

[[ $(uname -m) == "aarch64" && -f /etc/default/limine ]] || exit 0

# ARM also supports boot stacks such as Asahi's, so the runtime package cannot
# depend on Limine unconditionally. The ISO installs its chosen stack explicitly;
# older ARM installations can still have these packages marked as dependencies.
# Preserve only installed packages, without installing a different boot stack.
recovery_packages=()
for package in limine limine-mkinitcpio-hook limine-snapper-sync snapper; do
  if pacman -Qd "$package" &>/dev/null; then
    recovery_packages+=("$package")
  fi
done

if (( ${#recovery_packages[@]} )); then
  sudo pacman -D --asexplicit "${recovery_packages[@]}"
fi
