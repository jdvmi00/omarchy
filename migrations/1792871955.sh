echo "Install the GB10 power telemetry driver, so whole-system power shows in hwmon"

# Existing GB10 installs predate spark-hwmon-dkms in the GB10 package list.
# The sensors appear after the next boot, when udev loads the module for the
# NVDA8800 firmware device.
omarchy-hw-aarch64-gb10 || exit 0
omarchy-pkg-add spark-hwmon-dkms
