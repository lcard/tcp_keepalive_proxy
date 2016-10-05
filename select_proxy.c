#include <stdio.h>

#define NB_CONNECTION 50
#define DATABUFSIZE 10240

#if defined(_WIN32)
#pragma comment(lib, "Ws2_32.lib")
#include <winsock2.h>
#include <ws2tcpip.h>
#define close closesocket

static int
tcp_init_win32(void)
{
	/* Initialise Windows Socket API */
	WSADATA wsaData;

	if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
		printf("WSAStartup() returned error code %d\n",
			(unsigned int)GetLastError());
		errno = EIO;
		return -1;
	}
	return 0;
}
#endif

static SOCKET
tcp_listen(char * ip, char * port, int nb_connection)
{
	SOCKET new_sock;
	int rc;
	struct addrinfo hints, *res;

#if defined(_WIN32)
	if (tcp_init_win32() == -1) {
		return -1;
	}
#endif

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_INET;  // use IPv4.
	hints.ai_socktype = SOCK_STREAM;

	rc = getaddrinfo(ip, port, &hints, &res);
	if (rc != 0) {
		printf("getaddrinfo() failed with error %d.\n", rc);
		return -1;
	}

	// make a socket:
	new_sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
	if (new_sock == INVALID_SOCKET) {
		printf("socket() fail.");
		return -1;
	}


	// bind it to the port we passed in to getaddrinfo():
	if (bind(new_sock, res->ai_addr, res->ai_addrlen) == SOCKET_ERROR) {
		close(new_sock);
		printf("bind() fail.");
		return -1;
	}

	if (listen(new_sock, nb_connection) == SOCKET_ERROR) {
		close(new_sock);
		printf("listen() fail.");
		return -1;
	}

	return new_sock;
}

/* Util function to Shutdown, Close,  Clear from fd set, and Zero a socket. */
void
sccz(SOCKET * s, fd_set * set) {
	shutdown(*s, SD_BOTH);
	close(*s);
	FD_CLR(*s, set);
	*s = 0;
}

int
main (int argc, char ** argv) {

	char * listen_port_str = argv[1];
	char * server_ip = argv[2];
	char * server_port_str = argv[3];

	SOCKET listen_socket, client_socket, server_socket;
	fd_set socket_set, ready_set;
	SOCKET fdmax;

	printf("Listening on 127.0.0.1 port %s.\n", listen_port_str);
	printf("Redirecting connections to %s:%s.\n", server_ip, server_port_str);

	client_socket = 0;
	server_socket = 0;

	struct sockaddr_storage client_addr;
	socklen_t addr_size = sizeof client_addr;

	char data[DATABUFSIZE];
	int nbytes_recv, nbytes_sent;

	listen_socket = tcp_listen("127.0.0.1", listen_port_str, NB_CONNECTION);
	if (listen_socket < 0) {
		printf("Cannot create proxy socket.\n");
		exit(EXIT_FAILURE);
	}

	printf("Proxy server waiting for client connection on port %s\n", listen_port_str);

	FD_ZERO(&socket_set);
	FD_SET(listen_socket, &socket_set);
	fdmax = listen_socket;

SELECT:
	while(1) {
		ready_set = socket_set;
		if (select(fdmax+1, &ready_set, NULL, NULL, NULL) < 0)
		{
			printf("select() failure.\n");
			exit(EXIT_FAILURE);
		}

		for(SOCKET r=0; r<=fdmax; r++) {
			if(FD_ISSET(r, &ready_set)) {

				if (r == listen_socket) {
					// If we already have one, dump it for the new one.
					if (client_socket) {
						sccz(&client_socket, &socket_set);
					}

					client_socket = accept(listen_socket, (struct sockaddr *)&client_addr, &addr_size);
					if (client_socket == INVALID_SOCKET) {
						printf("accept() error.\n");
					} else {
						FD_SET(client_socket, &socket_set);
						if (client_socket > fdmax) {    // keep track of the max
							fdmax = client_socket;
						}
					}
				}

				if (r == client_socket) {
					memset(data, 0, sizeof data);
					if ( (nbytes_recv = recv(r, data, sizeof data, 0)) > 0) {

						printf("Received %i bytes from client.\n", nbytes_recv);

						int server_socket_retries = 10;
						struct addrinfo hints, *res;

						// first, load up address structs with getaddrinfo():
						memset(&hints, 0, sizeof hints);
						hints.ai_family = AF_UNSPEC;
						hints.ai_socktype = SOCK_STREAM;
						getaddrinfo(server_ip, server_port_str, &hints, &res);

						while (!server_socket) {
							// Send request to real server which closes connections:
							// Create a connecting socket to real server:

							// make a socket:
							server_socket = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
							if ((server_socket == INVALID_SOCKET ) || (connect(server_socket, res->ai_addr, res->ai_addrlen) == SOCKET_ERROR)) {
								printf("Cannot connect to the real server.\n");

								server_socket_retries--;
								server_socket = 0;

								if (server_socket_retries == 0) {
									printf("Exhausted retries connecting to server.\n");

									// Close client.
									printf("Close client socket and wait for new connection.\n");
									sccz(&client_socket, &socket_set);

									// Go back to select.
									goto SELECT;
								}
							} else {
								FD_SET(server_socket, &socket_set);
								if (server_socket > fdmax) {    // keep track of the max
									fdmax = server_socket;
								}
								printf("Connected to the real server.\n");
							}
						}

						nbytes_sent = send(server_socket, data, nbytes_recv, 0);
						if (nbytes_sent > 0) {
							printf("Sent %i to server.\n",  nbytes_sent);
						} else {
							printf("Server socket send() error. Did server close it on me? We just made sure this was open!\n");
						}

					} else {
						printf("Client socket recv() error. Did remote close it on me?\n");
						printf("Close client socket and wait for new connection.\n");
						sccz(&client_socket, &socket_set);
					}
				}

				if (r == server_socket) {
					memset(data, 0, sizeof data);
					if ((nbytes_recv = recv(r, data, sizeof data, 0)) >= 0) {

						if (client_socket && nbytes_recv) {
							printf("Received %i from server.\n", nbytes_recv);

							//Write it to client.
							nbytes_sent = send(client_socket, data, nbytes_recv, 0);

							if (nbytes_sent) {
								printf("Sent %i to client.\n", nbytes_sent);
							} else {
								printf("Client socket send() error. Did client close it on me?\n");
								printf("Close client socket and wait for new connection.\n");
								sccz(&client_socket, &socket_set);

							}

						} else {
							printf("Closing server socket.\n");
							sccz(&server_socket, &socket_set);
						}
					} else {
						sccz(&server_socket, &socket_set);
					}
				}
			}
		}
	}
	sccz(&listen_socket, &socket_set);
	return(0);
}