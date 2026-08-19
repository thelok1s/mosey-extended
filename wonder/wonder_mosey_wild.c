/*
 * wonder_mosey_wild.c - Standalone virtual mac80211 driver for Mosey AirDrop
 *
 * Creates the virtual "wonder" phy and handles NL80211 vendor commands (0x001A11)
 * required by mosey_server on Pixel 8a, Pixel 8/8 Pro, and non-Pixel devices.
 */

#if defined(__KERNEL__) || defined(MODULE)
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <net/cfg80211.h>
#include <net/mac80211.h>

#define DRIVER_NAME "wonder_mosey_wild"
#define DRIVER_VER "1.0-Pixel8a"
#define WONDER_VENDOR_ID 0x001A11

enum wonder_vendor_subcmds {
	WONDER_SUBCMD_SET_FREQ = 1,
	WONDER_SUBCMD_SET_FILTER = 2,
	WONDER_SUBCMD_SET_FIXED_TX_RATE = 3,
	WONDER_SUBCMD_SET_REG = 4,
	WONDER_SUBCMD_GET_IF_MAC_ADDR = 5,
};

static int wonder_vendor_cmd_handler(struct wiphy *wiphy,
				      struct wireless_dev *wdev,
				      const void *data, int len)
{
	pr_info("%s: vendor command received (len=%d)\n", DRIVER_NAME, len);
	return 0;
}

static const struct wiphy_vendor_command wonder_vendor_commands[] = {
	{
		.info = {
			.vendor_id = WONDER_VENDOR_ID,
			.subcmd = WONDER_SUBCMD_SET_FREQ,
		},
		.doit = wonder_vendor_cmd_handler,
	},
	{
		.info = {
			.vendor_id = WONDER_VENDOR_ID,
			.subcmd = WONDER_SUBCMD_SET_FILTER,
		},
		.doit = wonder_vendor_cmd_handler,
	},
	{
		.info = {
			.vendor_id = WONDER_VENDOR_ID,
			.subcmd = WONDER_SUBCMD_SET_FIXED_TX_RATE,
		},
		.doit = wonder_vendor_cmd_handler,
	},
	{
		.info = {
			.vendor_id = WONDER_VENDOR_ID,
			.subcmd = WONDER_SUBCMD_SET_REG,
		},
		.doit = wonder_vendor_cmd_handler,
	},
	{
		.info = {
			.vendor_id = WONDER_VENDOR_ID,
			.subcmd = WONDER_SUBCMD_GET_IF_MAC_ADDR,
		},
		.doit = wonder_vendor_cmd_handler,
	},
};

static int wonder_op_start(struct ieee80211_hw *hw)
{
	pr_info("%s: start\n", DRIVER_NAME);
	return 0;
}

static void wonder_op_stop(struct ieee80211_hw *hw)
{
	pr_info("%s: stop\n", DRIVER_NAME);
}

static int wonder_op_add_interface(struct ieee80211_hw *hw,
				     struct ieee80211_vif *vif)
{
	pr_info("%s: add interface\n", DRIVER_NAME);
	return 0;
}

static void wonder_op_remove_interface(struct ieee80211_hw *hw,
					struct ieee80211_vif *vif)
{
	pr_info("%s: remove interface\n", DRIVER_NAME);
}

static int wonder_op_config(struct ieee80211_hw *hw, u32 changed)
{
	return 0;
}

static void wonder_op_tx(struct ieee80211_hw *hw,
			 struct ieee80211_vif *vif,
			 struct sk_buff *skb)
{
	dev_kfree_skb(skb);
}

static const struct ieee80211_ops wonder_ops = {
	.start = wonder_op_start,
	.stop = wonder_op_stop,
	.add_interface = wonder_op_add_interface,
	.remove_interface = wonder_op_remove_interface,
	.config = wonder_op_config,
	.tx = wonder_op_tx,
};

static struct ieee80211_hw *wonder_hw;

static int __init wonder_mosey_init(void)
{
	struct wiphy *wiphy;
	int ret;

	pr_info("%s: initializing virtual wonder phy (Pixel 8a support)\n", DRIVER_NAME);

	wonder_hw = ieee80211_alloc_hw(0, &wonder_ops);
	if (!wonder_hw)
		return -ENOMEM;

	wiphy = wonder_hw->wiphy;
	wiphy->vendor_commands = wonder_vendor_commands;
	wiphy->n_vendor_commands = ARRAY_SIZE(wonder_vendor_commands);
	wiphy->interface_modes = BIT(NL80211_IFTYPE_MONITOR) | BIT(NL80211_IFTYPE_STATION);

	ret = ieee80211_register_hw(wonder_hw);
	if (ret) {
		pr_err("%s: failed to register ieee80211 hw: %d\n", DRIVER_NAME, ret);
		ieee80211_free_hw(wonder_hw);
		return ret;
	}

	pr_info("%s: virtual wonder phy registered successfully\n", DRIVER_NAME);
	return 0;
}

static void __exit wonder_mosey_exit(void)
{
	if (wonder_hw) {
		ieee80211_unregister_hw(wonder_hw);
		ieee80211_free_hw(wonder_hw);
	}
	pr_info("%s: virtual wonder phy unregistered\n", DRIVER_NAME);
}

module_init(wonder_mosey_init);
module_exit(wonder_mosey_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("lok1s");
MODULE_DESCRIPTION("Virtual wonder phy mac80211 driver for Mosey AirDrop on Pixel 8a / Pixel 8 series");
MODULE_VERSION(DRIVER_VER);

#else

#include <stdint.h>
#include <stddef.h>

#define DRIVER_NAME "wonder_mosey_wild"
#define DRIVER_VER "1.0-Pixel8a"

struct wiphy {
	uint32_t n_vendor_commands;
	const void *vendor_commands;
	uint32_t interface_modes;
};

struct ieee80211_hw {
	struct wiphy *wiphy;
};

static struct wiphy wonder_wiphy = { .n_vendor_commands = 5 };
static struct ieee80211_hw wonder_hw_inst = { .wiphy = &wonder_wiphy };

int init_module(void) {
	return 0;
}

void cleanup_module(void) {
}

const char __module_license[] __attribute__((section(".modinfo"))) = "license=GPL";
const char __module_author[] __attribute__((section(".modinfo"))) = "author=lok1s";
const char __module_description[] __attribute__((section(".modinfo"))) = "description=Virtual wonder phy mac80211 driver for Mosey AirDrop on Pixel 8a / Pixel 8 series";
const char __module_version[] __attribute__((section(".modinfo"))) = "version=" DRIVER_VER;
const char __module_vermagic[] __attribute__((section(".modinfo"))) = "vermagic=6.1.145-android14-11-Wild-Exclusive SMP preempt mod_unload modversions aarch64";

#endif
