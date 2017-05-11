#include "erl_interface.h"
#include "ei.h"    

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <getopt.h>

#ifdef GPU_CNODE
extern int dotProduct(float *A, float *B, int len, float *C);
#include <helper_functions.h>
#include <helper_cuda.h>
#else
int dotProduct(float *A, float *B, int len, float *C);
#endif

#include "cnode.h"

int main(int argc, char *argv[]) {

	int port, fd, listen_fd, pub;
	int option = 0;
	ErlConnect conn;
	char *ip_addr, *hostname, *nodename, *fullnodename, *cookie;


	port = 0;
	while ((option = getopt(argc, argv,"p:i:h:n:f:c:")) != -1) {
		switch (option) {
			case 'i' : ip_addr = optarg;
			break;
			case 'h' : hostname = optarg;
	 		break;
     			case 'n' : nodename = optarg; 
	 		break;
			case 'f' : fullnodename = optarg;
			break;
			case 'c' : cookie = optarg;
			break;
			case 'p' : port = atoi(optarg);
			break;
			default: print_usage(); 
			exit(-1);
		}
	}

	if (port == 0) {
		print_usage();
		exit(-1);
	}

	if ((listen_fd = cnode_listen(port)) == -1) {
		erl_err_quit("cnode listen");
	}
	fprintf(stdout, "listening on port %d\n", port);

	erl_init(NULL,0);

	if (cnode_connect(ip_addr, hostname, nodename, fullnodename, cookie) == -1) {
		erl_err_quit("cnode connect");
	}
	fprintf(stdout, "connecting\n");

	if ((pub = erl_publish(port)) == -1) {
		erl_err_quit("erl_publish");
	}
	fprintf(stdout, "publishing on port %d\n", port);

	fprintf(stdout, "waiting on accept...\n");

	while (1) {
		if ((fd = erl_accept(listen_fd, &conn)) == ERL_ERROR) {
			erl_err_quit("erl_accept");
		}

		fprintf(stdout, "Connected to %s\n\r", conn.nodename);

		pid_t parent = getpid();
		pid_t pid = fork();

		if (pid == -1) {
		} else if (pid > 0) {
			close(fd);
			continue;
		} else {

#ifdef GPU_CNODE
    			findCudaDevice(argc, (const char **)argv);
#endif
			cnode_process(fd);
			close(fd);
		}
	}



	exit(0);
}

void print_usage() {
    printf("Usage: cnode -p port -i ip_addr -h hostname -n nodename -f longnodename -c cookie\n");
}

int cnode_connect(char *ip_addr, char *hostname, char *nodename, char *fullnodename, char *cookie) {

	struct in_addr addr;

	//The first argument is the host name.
	//The second argument is the plain node name.
	//The third argument is the full node name.
	//The fourth argument is a pointer to an in_addr struct with the IP address of the host.
	//The fifth argument is the magic cookie.
	//The sixth argument is the instance number.

	addr.s_addr = inet_addr(ip_addr);
	if (erl_connect_xinit(hostname, nodename, fullnodename, &addr, cookie, 0) == -1) {
		erl_err_quit("erl_connect_xinit");
	}

	return 0;
}

int cnode_listen(int port) {
	int listen_fd;
	struct sockaddr_in addr;
	int on = 1;

	if ((listen_fd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
		return (-1);
	}

	setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));

	memset((void*) &addr, 0, (size_t) sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = htonl(INADDR_ANY);

	if (bind(listen_fd, (struct sockaddr*) &addr, sizeof(addr)) < 0)
		return (-1);
	
	listen(listen_fd, 5);

	return listen_fd;
}


void cnode_process(int fd) {

	int loop = 1;                            /* Loop flag */
	int got;                                 /* Result of receive */
	unsigned char buf[BUFSIZE];              /* Buffer for incoming message */
	ErlMessage emsg;                         /* Incoming message */

	ETERM *msg, *fromp, *tuplep, *fnp, *arga, *argb, *resp;
	int res, *static_res_array;
	ETERM *gen_call         = erl_format("~a", "$gen_call");

	while (loop) {

		got = erl_receive_msg(fd, buf, BUFSIZE, &emsg);
		if (got == ERL_TICK) {
			fprintf(stdout, "got an ERL_TICK: ignoring...\n");
		} else if (got == ERL_ERROR) {
			fprintf(stdout, "got an ERL_ERROR: terminating processing...\n");
			loop = 0;
		} else {

			if (emsg.type == ERL_REG_SEND) {
				msg = erl_element(1, emsg.msg);
				fromp = erl_element(2, emsg.msg);
				tuplep = erl_element(3, emsg.msg);

				fnp = erl_element(1, tuplep);
				arga = erl_element(2, tuplep);
				argb = erl_element(3, tuplep);

				if (erl_match(gen_call, msg)) {
					process_gen_call(fd, emsg.from, emsg.msg);
					continue;
				}

				if (strncmp(ERL_ATOM_PTR(fnp), "dot", 3) == 0) {

					int error = 0;
					float *array_a, *array_b;

					if (ERL_IS_CONS(arga) && ERL_IS_CONS(argb) && (erl_length(arga) == erl_length(argb))) {
						array_a = make_float_array(arga);
						array_b = make_float_array(argb);

						int i;

						if (array_a == NULL) {
							error = 1;
						}

						if (array_b == NULL) {
							error = 1;
						}

					} else {
						error = 1;
					}

					if (!error) {
						float C;

						dotProduct(array_a, array_b, erl_length(arga), &C);
						resp = erl_format("{cnode, ~f}", C);
						erl_send(fd, fromp, resp);
					} else {
						ETERM *err;
						err = erl_format("{cnode, ~w}", erl_format("[{err, ~a}]", "error_in_args"));
						erl_send(fd, fromp, err);
						erl_free_compound(err);
					}

					free(array_a);
					free(array_b);

				} else {
					fprintf(stdout, "received unknown atom: %s\n", ERL_ATOM_PTR(fnp));
				}	


				erl_free_term(msg);
				erl_free_term(emsg.from); erl_free_term(emsg.msg);
				erl_free_term(fromp); erl_free_term(tuplep);
				erl_free_term(fnp); erl_free_term(arga); erl_free_term(argb);
				erl_free_term(resp);

				erl_mem_manager_report();
			}
		}
	}
	erl_free_term(gen_call);
	fprintf(stdout,"node terminating\n");
}

static void erl_mem_manager_report() {
	unsigned long allocated, freed;

	erl_eterm_statistics(&allocated,&freed);
	printf("currently allocated blocks: %ld\n",allocated);
	printf("length of freelist: %ld\n",freed);

	/* really free the freelist */
	erl_eterm_release();
}

static void process_gen_call(int fd, ETERM *from, ETERM *msg) {
	ETERM *is_auth  = erl_format("~a", "is_auth");
	ETERM *args = erl_element(3, msg);
	ETERM *arg1 = erl_element(1, args);

	if (erl_match(is_auth, arg1)) {
		ETERM *fromp = erl_element(2, msg);
		ETERM *resp = erl_format("{~w, yes}", erl_element(2, fromp));
		erl_send(fd, from, resp);
		fprintf(stdout, "responded to a ping...\n");
		erl_free_compound(resp);
		erl_free_term(fromp);
	}
	erl_free_term(args);
	erl_free_term(arg1);
	erl_free_term(is_auth);
}


ETERM **array_to_list(int *static_res_array, int length) {

	ETERM **list = (ETERM **)malloc(sizeof(ETERM *) * length);
	int i;

	for(i=0;i<length;i++) {
		list[i] = erl_mk_int(static_res_array[i]);
	}
	return list;
}

void free_list(ETERM **list, int length) {
	int i;

	fprintf(stdout, "freeing: %d\n", length);
	for (i=0;i<length; i++) {
		erl_free_term(list[i]);
	}
	free(list);
}


float *make_float_array(ETERM *argp) {
	int i;
	float *array = (float *)malloc(erl_length(argp)*sizeof(float));
	ETERM *hd, *tl, *nt;

	for (
		i=0, hd=erl_hd(argp), tl=erl_tl(argp);

		i<erl_length(argp);

		i++,

		erl_free_term(hd),
		hd=erl_hd(tl), 
		nt=erl_tl(tl),
		erl_free_term(tl),
		tl=nt)
	{
		if (ERL_IS_INTEGER(hd)) {
			array[i]=(int)ERL_INT_VALUE(hd);
		}
		else if (ERL_IS_FLOAT(hd)) {
			array[i]=ERL_FLOAT_VALUE(hd);
		} else {
			erl_free_term(hd); erl_free_term(tl);
			return (float *)NULL;
		}
	}

	erl_free_term(hd);
	erl_free_term(tl);

	return array;
}

int *make_int_array(ETERM *argp) {
	int i;
	int *array = (int *)malloc(erl_length(argp)*sizeof(int));
	ETERM *hd, *tl, *nt;

	for (
		i=0, hd=erl_hd(argp), tl=erl_tl(argp);

		i<erl_length(argp);

		i++,

		erl_free_term(hd),
		hd=erl_hd(tl), 
		nt=erl_tl(tl),
		erl_free_term(tl),
		tl=nt)
	{
		if (ERL_IS_INTEGER(hd)) {
			array[i]=ERL_INT_VALUE(hd);
		}
		else {
			erl_free_term(hd); erl_free_term(tl);
			return (int *)NULL;
		}
	}

	erl_free_term(hd);
	erl_free_term(tl);

	return array;
}

#ifndef GPU_CNODE
int dotProduct(float *A, float *B, int len, float *C) {
	int i;
	float dp;

	for (i=0;i<len;i++) {
		dp += (A[i]*B[i]);
	}
	*C = dp;
	return 0;
}
#endif
