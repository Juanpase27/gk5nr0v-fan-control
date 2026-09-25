// SPDX-License-Identifier: GPL-2.0
/*
 * gk5nr0v-fans - read-only hwmon exposure of TongFang GK5NR0V (EVOO EG-LP7)
 * fan tachometers behind the Insyde ACPI Embedded Controller.
 *
 * Register map (reverse engineered in the gk5nr0v-fan-control project):
 *   0x60-0x61  CPU fan RPM, 16-bit big-endian
 *   0x68-0x69  GPU fan RPM, 16-bit big-endian (0 = dGPU fan-stop)
 *
 * Reads go through the in-kernel ACPI EC driver (ec_read), which serializes
 * transactions with any other EC user (nbfc writing duty 0x3E via ec_sys),
 * so this module coexists with nbfc-linux control.
 *
 * Strictly read-only: no EC writes, no pwm channels, no firmware fighting.
 * Monitoring only - control stays with nbfc-linux + the v2 curve config.
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/hwmon.h>
#include <linux/acpi.h>

#define EC_CPU_TACH_HI	0x60
#define EC_CPU_TACH_LO	0x61
#define EC_GPU_TACH_HI	0x68
#define EC_GPU_TACH_LO	0x69

enum gk5nr0v_fan_channel {
	FAN_CPU = 0,
	FAN_GPU = 1,
};

static int gk5nr0v_read_tach(int channel, long *val)
{
	u8 hi, lo;
	u8 base = (channel == FAN_CPU) ? EC_CPU_TACH_HI : EC_GPU_TACH_HI;
	int ret;

	ret = ec_read(base, &hi);
	if (ret)
		return ret;
	ret = ec_read(base + 1, &lo);
	if (ret)
		return ret;

	*val = (hi << 8) | lo;
	return 0;
}

static int gk5nr0v_read(struct device *dev, enum hwmon_sensor_types type,
			u32 attr, int channel, long *val)
{
	switch (type) {
	case hwmon_fan:
		if (attr == hwmon_fan_input)
			return gk5nr0v_read_tach(channel, val);
		return -EOPNOTSUPP;
	default:
		return -EOPNOTSUPP;
	}
}

static int gk5nr0v_read_string(struct device *dev,
			       enum hwmon_sensor_types type, u32 attr,
			       int channel, const char **str)
{
	switch (channel) {
	case FAN_CPU:
		*str = "CPU fan";
		return 0;
	case FAN_GPU:
		*str = "GPU fan";
		return 0;
	default:
		return -EOPNOTSUPP;
	}
}

static umode_t gk5nr0v_is_visible(const void *data,
				  enum hwmon_sensor_types type, u32 attr,
				  int channel)
{
	if (type == hwmon_fan && attr == hwmon_fan_input)
		return 0444;
	if (type == hwmon_fan && attr == hwmon_fan_label)
		return 0444;
	return 0;
}

static const u32 gk5nr0v_fan_config[] = {
	HWMON_F_INPUT | HWMON_F_LABEL,
	HWMON_F_INPUT | HWMON_F_LABEL,
	0
};

static const struct hwmon_channel_info gk5nr0v_fans = {
	.type = hwmon_fan,
	.config = gk5nr0v_fan_config,
};

static const struct hwmon_channel_info *gk5nr0v_info[] = {
	&gk5nr0v_fans,
	NULL
};

static const struct hwmon_ops gk5nr0v_ops = {
	.is_visible = gk5nr0v_is_visible,
	.read = gk5nr0v_read,
	.read_string = gk5nr0v_read_string,
};

static const struct hwmon_chip_info gk5nr0v_chip = {
	.ops = &gk5nr0v_ops,
	.info = gk5nr0v_info,
};

static struct platform_device *gk5nr0v_pdev;

static int __init gk5nr0v_init(void)
{
	struct device *hdev;
	int ret;

	gk5nr0v_pdev = platform_device_register_simple("gk5nr0v_fans",
						       PLATFORM_DEVID_NONE,
						       NULL, 0);
	if (IS_ERR(gk5nr0v_pdev))
		return PTR_ERR(gk5nr0v_pdev);

	hdev = devm_hwmon_device_register_with_info(&gk5nr0v_pdev->dev,
						    "gk5nr0v_fans", NULL,
						    &gk5nr0v_chip, NULL);
	if (IS_ERR(hdev)) {
		ret = PTR_ERR(hdev);
		platform_device_unregister(gk5nr0v_pdev);
		return ret;
	}

	return 0;
}

static void __exit gk5nr0v_exit(void)
{
	platform_device_unregister(gk5nr0v_pdev);
}

module_init(gk5nr0v_init);
module_exit(gk5nr0v_exit);

MODULE_AUTHOR("Juan <Juanpase27@users.noreply.github.com>");
MODULE_DESCRIPTION("Read-only hwmon exposure of TongFang GK5NR0V fan tachometers (EC 0x60/0x68)");
MODULE_LICENSE("GPL");
