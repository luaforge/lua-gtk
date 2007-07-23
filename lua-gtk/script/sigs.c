/* vim:sw=4:sts=4
 */
#include <gtk/gtk.h>
#include <stdio.h>

void process_class(const char *name, GType itype)
{
    guint *ids, n_ids, signal_id;
    GSignalQuery query;
    gpointer *cls;
    int param_nr, signal_shown;

    cls = g_type_class_ref(itype);
    ids = g_signal_list_ids(itype, &n_ids);

    while (n_ids--) {
	signal_id = *ids++;

	g_signal_query(signal_id, &query);
	if (query.signal_id == 0) {
	    printf("Invalid signal %d for %s!\n", signal_id, name);
	    continue;
	}

	/* which parameters are of type G_TYPE_POINTER? */
	signal_shown = 0;
	for (param_nr=0; param_nr<query.n_params; param_nr++) {
	    if (query.param_types[param_nr] == G_TYPE_POINTER) {
		if (!signal_shown) {
		    printf("%s::%s", name, query.signal_name);
		    signal_shown = 1;
		}
		printf(" %d", param_nr);
	    }
	}

	if (signal_shown)
	    printf("\n");

    }
    g_type_class_unref(cls);
}


void process_tree(const char *name, GType type)
{
    GType *types;
    guint n_children, i;

    if (!type)
	type = g_type_from_name(name);

    if (type == 0) {
	printf("Unknown object type %s\n", name);
	return;
    }

    if (!name)
	name = g_type_name(type);

    process_class(name, type);

    types = g_type_children(type, &n_children);
    for (i=0; i<n_children; i++) {
	type = types[i];
	name = g_type_name(type);
	process_tree(name, type);
    }

    g_free(types);
}

void init_all_types()
{
    GType t;
    #include "sigs-list.c"
}

int main(int argc, char **argv)
{
    g_type_init();
    init_all_types();
    process_tree("GObject", 0);
    return 0;
}


