/*
 * rename_phy.c - NL80211 phy rename utility
 *
 * Renames virtual mac80211 phy to "wonder" for mosey_server initialization.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/genetlink.h>

#define NL80211_GENL_NAME "nl80211"

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <phy_index> <new_name>\n", argv[0]);
        return 1;
    }

    const char *phy_idx = argv[1];
    const char *new_name = argv[2];

    printf("[rename_phy] Renaming phy%s to %s\n", phy_idx, new_name);

    /* System fallback using iw command */
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "iw phy phy%s set name %s 2>/dev/null || iw phy %s set name %s 2>/dev/null",
             phy_idx, new_name, phy_idx, new_name);
    
    int rc = system(cmd);
    if (rc == 0) {
        printf("[rename_phy] Successfully renamed phy%s to %s\n", phy_idx, new_name);
        return 0;
    }

    fprintf(stderr, "[rename_phy] Failed to rename phy%s to %s (rc=%d)\n", phy_idx, new_name, rc);
    return rc;
}
