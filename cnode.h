
#define LENGTH(o) (sizeof(o)/sizeof(o[0]))
#define BUFSIZE 1000

int cnode_listen(int port);
int cnode_connect(char *ip_addr, char *hostname, char *nodename, char *fullnodename, char *cookie);
void cnode_process(int fd);
static void process_gen_call(int fd, ETERM *from, ETERM *msg);
ETERM **array_to_list(int *static_res_array, int length);
void free_list(ETERM **list, int length);
void print_usage();
static void erl_mem_manager_report();
int *make_int_array(ETERM *argp);
float *make_float_array(ETERM *argp);

int foo(int p);
static int* bar(int p);

