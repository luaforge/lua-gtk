/** vim:sw=4:sts=4
 * Public functions for the hash tables.
 */

struct hash_info;
const unsigned char *hash_search(const struct hash_info *hi, const char *key,
	int keylen, int *datalen);

/* external tables with hash data */
extern const struct hash_info hash_info_funcs;
extern const struct hash_info hash_info_enums;

